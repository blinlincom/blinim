#!/usr/bin/env python3
"""Ensure admin/API uploads use the selected application's OSS configuration."""

from datetime import datetime
from pathlib import Path
import os
import re
import shutil


ROOT = Path(os.environ.get("BLIN_ROOT", "/www/wwwroot/blinlin"))
UPLOAD = ROOT / "application/common/tool/Upload.php"
ADMIN_INDEX = ROOT / "application/admin/controller/Index.php"
API = ROOT / "application/api/controller/Api.php"


def backup(path: Path, suffix: str) -> None:
    if not path.exists():
        return
    stamp = datetime.now().strftime("%Y%m%d%H%M%S")
    shutil.copy2(path, path.with_name(f"{path.name}.bak_{suffix}_{stamp}"))


def save(path: Path, text: str, suffix: str) -> bool:
    old = path.read_text(encoding="utf-8", errors="ignore")
    if old == text:
        return False
    backup(path, suffix)
    path.write_text(text, encoding="utf-8")
    return True


def replace_method(source: str, name: str, body: str) -> str:
    match = re.search(rf"    public function {re.escape(name)}\s*\([^)]*\)\s*\{{", source)
    if not match:
        raise RuntimeError(f"missing method {name}")
    start = match.start()
    depth = 0
    end = None
    for index in range(match.end() - 1, len(source)):
        char = source[index]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                end = index + 1
                break
    if end is None:
        raise RuntimeError(f"unterminated method {name}")
    return source[:start] + body.rstrip() + source[end:]


UPLOAD_CLASS = r'''<?php

namespace app\common\tool;

use think\Db;

class Upload
{
    private $upload_system = [];
    private $uploader_id = 0;
    private $uploader = 0;
    private $appid = 0;

    public function __construct($uploader_id = 0, $appid = 0)
    {
        $this->appid = $this->resolveAppid($appid, $uploader_id);
        if ($uploader_id == 0) {
            $this->uploader = 0;
            $this->uploader_id = session("admin.id");
        } else {
            $this->uploader = 1;
            $this->uploader_id = $uploader_id;
        }
        $this->upload_system = $this->normalizedUploadConfig(AppScopedConfig::upload($this->appid));
    }

    protected function resolveAppid($appid, $uploaderId = 0)
    {
        $appid = intval($appid);
        if ($appid > 0) return $appid;
        try {
            $appid = intval(request()->param("appid") ?: request()->post("appid") ?: request()->get("appid"));
        } catch (\Throwable $th) {
            $appid = 0;
        }
        if ($appid > 0) return $appid;
        if (intval($uploaderId) > 0) {
            try {
                $user = Db::name("user")->where("id", intval($uploaderId))->field("appid")->find();
                if ($user && intval($user["appid"]) > 0) return intval($user["appid"]);
            } catch (\Throwable $th) {
            }
        }
        try {
            $adminId = intval(session("admin.id"));
            if ($adminId > 0) {
                $admin = Db::name("admin")->where("id", $adminId)->find();
                if ($admin) {
                    $frontAppid = intval(isset($admin["front_appid"]) ? $admin["front_appid"] : 0);
                    if ($frontAppid > 0) return $frontAppid;
                    if (intval(isset($admin["role_id"]) ? $admin["role_id"] : 0) !== 0) {
                        $raw = strval(isset($admin["managed_appids"]) ? $admin["managed_appids"] : "");
                        $parts = preg_split("/[,，\s]+/", $raw);
                        foreach ($parts as $part) {
                            $id = intval($part);
                            if ($id > 0) return $id;
                        }
                    }
                }
            }
        } catch (\Throwable $th) {
        }
        try {
            $app = Db::name("app")->field("appid")->order("appid", "asc")->find();
            if ($app && intval($app["appid"]) > 0) return intval($app["appid"]);
        } catch (\Throwable $th) {
        }
        return 0;
    }

    protected function normalizedUploadConfig($config)
    {
        if (!is_array($config)) $config = [];
        $defaults = config("upload.");
        if (!is_array($defaults)) $defaults = [];
        $config = array_merge($defaults, $config);
        $config["file_extension"] = isset($config["file_extension"]) && trim(strval($config["file_extension"])) !== "" ? $config["file_extension"] : "jpg,jpeg,png,gif,zip,apk,mp4,m4a,aac,mp3,wav,amr,3gp,ogg,opus";
        $config["file_path"] = isset($config["file_path"]) && trim(strval($config["file_path"])) !== "" ? trim(strval($config["file_path"]), "/") : "uploads";
        $config["file_size"] = isset($config["file_size"]) && trim(strval($config["file_size"])) !== "" ? $config["file_size"] : "2000MB";
        $config["upload_space"] = intval(isset($config["upload_space"]) ? $config["upload_space"] : 0);
        $config["save_local"] = intval(isset($config["save_local"]) ? $config["save_local"] : 0);
        return $config;
    }

    public function upload($filename)
    {
        if (empty($_FILES) || empty($_FILES[$filename])) {
            throw new \Exception("上传文件为空");
        }
        $file = request()->file($filename);
        if (is_array($file)) {
            $result = [];
            foreach ($file as $item) {
                $result[] = $this->uploadDifferentSpaces($item);
            }
            return $result;
        }
        return $this->uploadDifferentSpaces($file);
    }

    public function check($file)
    {
        $detail = $file->getInfo();
        $file_size = convertFileSize($this->upload_system["file_size"]);
        if ($detail["size"] > $file_size) {
            throw new \Exception("上传文件大小超过限制");
        }
        $name = pathinfo($detail["name"]);
        $ext = strtolower(isset($name["extension"]) ? $name["extension"] : "");
        $allowed = array_filter(array_map("trim", explode(",", strtolower($this->upload_system["file_extension"]))));
        if (!in_array($ext, $allowed)) {
            throw new \Exception("上传文件扩展名不允许");
        }
    }

    public function save($file)
    {
        $info = $file->move($this->upload_system["file_path"]);
        if ($info) {
            return $this->upload_system["file_path"] . '/' . str_replace("\\", "/", $info->getSaveName());
        }
        throw new \Exception("文件上传失败");
    }

    public function uploadDifferentSpaces($file)
    {
        $this->check($file);
        $uploadFileAddress = intval($this->upload_system['upload_space']);
        $uploadPath = $this->upload_system["file_path"];
        $detail = $file->getInfo();
        if ($uploadFileAddress == 0) {
            $filePath = $this->save($file);
            $url = request()->domain() . "/" . ltrim($filePath, "/");
            $key = $filePath;
        } else {
            $localPath = "";
            if (intval($this->upload_system["save_local"]) == 0) {
                $localPath = $this->save($file);
            }
            if ($uploadFileAddress == 1) {
                $oss = new AlibabaCloudOSS($this->appid);
                $result = $oss->uploadFile($file, $uploadPath, $localPath);
            } elseif ($uploadFileAddress == 2) {
                $oss = new QCloudOSS($this->appid);
                $result = $oss->uploadFile($file, $uploadPath, $localPath);
            } elseif ($uploadFileAddress == 3) {
                $oss = new UpYunOSS($this->appid);
                $result = $oss->uploadFile($file, $uploadPath, $localPath);
            } elseif ($uploadFileAddress == 4) {
                $oss = new QiniuOSS($this->appid);
                $result = $oss->uploadFile($file, $uploadPath, $localPath);
            } else {
                throw new \Exception("上传空间配置错误");
            }
            if (!is_array($result) || empty($result['oss_path'])) {
                throw new \Exception(is_string($result) ? $result : "云存储上传失败");
            }
            $url = $result['oss_path'];
            $key = $result['file_path'];
        }
        $result = [
            'name' => $detail["name"],
            'type' => $detail["type"],
            'size' => $detail["size"],
            'filePath' => $url,
            'oss_type' => $uploadFileAddress,
            'key' => $key,
        ];
        $this->write_file_sql($result);
        return $result;
    }

    public function write_file_sql($result)
    {
        $result["appid"] = $this->appid;
        $result["create_time"] = date("Y-m-d H:i:s", time());
        $result["uploader_id"] = $this->uploader_id;
        $result["uploader"] = $this->uploader;
        Db::name("file")->insert($result);
    }
}
'''


ADMIN_UPLOAD = r'''    public function upload()
    {
        try {
            $appid = $this->blinResolveUploadAppid();
            if ($appid > 0 && method_exists($this, "blinRequireApp")) $this->blinRequireApp($appid);
            $upload = new Upload(0, $appid);
            $result = $upload->upload('file');
            $result = [
                'code' => 1,
                'msg'  => '上传成功',
                'data' => $result
            ];
            return $result;
        } catch (\Exception $th) {
            return $this->error($th->getMessage());
        }
    }

    private function blinResolveUploadAppid()
    {
        $appid = intval(input("appid") ?: input("post.appid") ?: input("get.appid"));
        if ($appid > 0) return $appid;
        $referer = isset($_SERVER["HTTP_REFERER"]) ? strval($_SERVER["HTTP_REFERER"]) : "";
        if ($referer !== "") {
            $parts = parse_url($referer);
            if (isset($parts["query"])) {
                parse_str($parts["query"], $query);
                if (isset($query["appid"]) && intval($query["appid"]) > 0) return intval($query["appid"]);
            }
        }
        if (isset($this->admin_info["front_appid"]) && intval($this->admin_info["front_appid"]) > 0) {
            return intval($this->admin_info["front_appid"]);
        }
        if (method_exists($this, "blinScopedAppList")) {
            $apps = $this->blinScopedAppList();
            if ($apps && isset($apps[0]["appid"])) return intval($apps[0]["appid"]);
        }
        $app = Db::name("app")->field("appid")->order("appid", "asc")->find();
        return $app && isset($app["appid"]) ? intval($app["appid"]) : 0;
    }
'''


def patch_admin_index() -> bool:
    source = ADMIN_INDEX.read_text(encoding="utf-8", errors="ignore")
    updated = source
    updated = replace_method(updated, "upload", ADMIN_UPLOAD)
    if "private function blinResolveUploadAppid()" not in source and "private function blinResolveUploadAppid()" not in updated:
        raise RuntimeError("admin upload appid resolver missing after patch")
    return save(ADMIN_INDEX, updated, "upload_oss_app_scope")


def patch_api_uploads() -> bool:
    source = API.read_text(encoding="utf-8", errors="ignore")
    updated = re.sub(
        r"new Upload\(\$user_all_info\[['\"]id['\"]\]\)",
        'new Upload($user_all_info[\'id\'], intval($user_all_info[\'appid\']))',
        source,
    )
    updated = re.sub(
        r"new Upload\(\$user_all_info\[\"id\"\]\)",
        'new Upload($user_all_info["id"], intval($user_all_info["appid"]))',
        updated,
    )
    updated = re.sub(
        r"new Upload\(\$userinfo\[[\"']id[\"']\]\)",
        'new Upload($userinfo["id"], intval($userinfo["appid"]))',
        updated,
    )
    return save(API, updated, "api_upload_oss_app_scope")


def main() -> None:
    changed = False
    changed = save(UPLOAD, UPLOAD_CLASS, "upload_oss_app_scope") or changed
    changed = patch_admin_index() or changed
    changed = patch_api_uploads() or changed
    print("PATCHED_UPLOAD_OSS_APP_SCOPE" if changed else "UPLOAD_OSS_APP_SCOPE_ALREADY_OK")


if __name__ == "__main__":
    main()
