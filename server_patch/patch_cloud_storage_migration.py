#!/usr/bin/env python3
"""Add bidirectional storage migration for local files and configured OSS providers."""

from datetime import datetime
from pathlib import Path
import os
import re
import shutil


ROOT = Path(os.environ.get("BLIN_ROOT", "/www/wwwroot/blinlin"))
TOOL_DIR = ROOT / "application/common/tool"
SYSTEM = ROOT / "application/admin/controller/System.php"
UPLOAD_VIEW = ROOT / "application/admin/view/system/upload.html"

MIGRATOR = r'''<?php

namespace app\common\tool;

use OSS\OssClient;
use Qcloud\Cos\Client as QCloudClient;
use Qiniu\Auth as QiniuAuth;
use Qiniu\Storage\UploadManager as QiniuUploadManager;
use think\Db;
use think\facade\Env;

class CloudStorageMigrator
{
    protected $appid = 0;
    protected $uploadConfig = [];
    protected $ossConfig = [];
    protected $rootPath = "";
    protected $publicPath = "";
    protected $domain = "";
    protected $logs = [];
    protected $tables = [
        "file", "user", "user_information_review", "messages", "im_group_messages",
        "im_groups", "im_moments", "shop_products", "order_records", "app",
        "app_download", "apps", "apps_version", "forum_posts",
    ];

    public function __construct($appid, $domain = "")
    {
        $this->appid = intval($appid);
        $this->uploadConfig = AppScopedConfig::upload($this->appid);
        $this->ossConfig = AppScopedConfig::oss($this->appid);
        $this->rootPath = rtrim(Env::get("root_path"), "/") . "/";
        $this->publicPath = $this->rootPath . "public/";
        $this->domain = rtrim($domain ?: request()->domain(), "/");
    }

    public function migrate($limit = 50)
    {
        $limit = $this->normalizeLimit($limit);
        $rows = Db::name("file")
            ->where("appid", $this->appid)
            ->where("oss_type", ">", 0)
            ->order("id", "asc")
            ->limit($limit)
            ->select();
        $ok = 0;
        $fail = 0;
        foreach ($rows as $row) {
            try {
                if ($this->migrateRowToLocal($row)) $ok++;
            } catch (\Throwable $th) {
                $fail++;
                $this->log("cloud-to-local file#" . intval($row["id"]) . " " . $th->getMessage());
            }
        }
        return [
            "processed" => count($rows),
            "success" => $ok,
            "failed" => $fail,
            "remaining" => Db::name("file")->where("appid", $this->appid)->where("oss_type", ">", 0)->count(),
            "logs" => array_slice($this->logs, -20),
        ];
    }

    public function migrateLocalToCloud($targetSpace = 0, $limit = 50)
    {
        $targetSpace = intval($targetSpace);
        if ($targetSpace <= 0) {
            $targetSpace = intval(isset($this->uploadConfig["upload_space"]) ? $this->uploadConfig["upload_space"] : 0);
        }
        if (!in_array($targetSpace, [1, 2, 3, 4], true)) {
            throw new \Exception("请选择要迁移到的OSS空间");
        }
        $limit = $this->normalizeLimit($limit);
        $rows = Db::name("file")
            ->where("appid", $this->appid)
            ->where("oss_type", 0)
            ->order("id", "asc")
            ->limit($limit)
            ->select();
        $ok = 0;
        $fail = 0;
        foreach ($rows as $row) {
            try {
                if ($this->migrateRowToCloud($row, $targetSpace)) $ok++;
            } catch (\Throwable $th) {
                $fail++;
                $this->log("local-to-cloud file#" . intval($row["id"]) . " " . $th->getMessage());
            }
        }
        return [
            "processed" => count($rows),
            "success" => $ok,
            "failed" => $fail,
            "remaining" => Db::name("file")->where("appid", $this->appid)->where("oss_type", 0)->count(),
            "logs" => array_slice($this->logs, -20),
        ];
    }

    protected function migrateRowToLocal($row)
    {
        $key = $this->cleanKey(isset($row["key"]) ? $row["key"] : "");
        if ($key === "") $key = $this->keyFromUrl(isset($row["filePath"]) ? $row["filePath"] : "");
        if ($key === "") throw new \Exception("缺少云端文件路径");
        $relative = $this->localRelativePath($key, isset($row["name"]) ? $row["name"] : "");
        $absolute = $this->publicPath . $relative;
        if (!is_file($absolute) || filesize($absolute) <= 0) {
            $this->ensureDir(dirname($absolute));
            $downloadUrl = $this->downloadUrl($row, $key);
            if (!$this->downloadToFile($downloadUrl, $absolute)) {
                throw new \Exception("下载云端文件失败");
            }
        }
        $oldUrl = strval(isset($row["filePath"]) ? $row["filePath"] : "");
        $newUrl = $this->domain . "/" . ltrim($relative, "/");
        Db::name("file")->where("id", intval($row["id"]))->update([
            "filePath" => $newUrl,
            "key" => $relative,
            "oss_type" => 0,
        ]);
        $this->replaceUrlVariants($oldUrl, $newUrl);
        return true;
    }

    protected function migrateRowToCloud($row, $targetSpace)
    {
        $oldUrl = strval(isset($row["filePath"]) ? $row["filePath"] : "");
        $relative = $this->localRelativeFromRow($row);
        $absolute = $this->publicPath . $relative;
        if (!is_file($absolute) || filesize($absolute) <= 0) {
            throw new \Exception("本地文件不存在");
        }
        $key = $this->cloudKeyFromLocal($relative, isset($row["name"]) ? $row["name"] : "");
        $mime = $this->mimeType($absolute, isset($row["type"]) ? $row["type"] : "");
        $result = $this->uploadToCloud($targetSpace, $absolute, $key, $mime);
        if (empty($result["file_path"]) || empty($result["oss_path"])) {
            throw new \Exception("OSS上传结果异常");
        }
        Db::name("file")->where("id", intval($row["id"]))->update([
            "filePath" => $result["oss_path"],
            "key" => $result["file_path"],
            "oss_type" => $targetSpace,
        ]);
        $this->replaceUrlVariants($oldUrl, $result["oss_path"]);
        return true;
    }

    protected function uploadToCloud($targetSpace, $absolute, $key, $mime)
    {
        if ($targetSpace === 1) return $this->uploadAliyun($absolute, $key, $mime);
        if ($targetSpace === 2) return $this->uploadQcloud($absolute, $key);
        if ($targetSpace === 3) return $this->uploadUpyun($absolute, $key);
        if ($targetSpace === 4) return $this->uploadQiniu($absolute, $key, $mime);
        throw new \Exception("上传空间配置错误");
    }

    protected function uploadAliyun($absolute, $key, $mime)
    {
        $cfg = AppScopedConfig::oss($this->appid, "alibabaOss");
        foreach (["accessKeyId", "accessKeySecret", "endpoint", "bucket"] as $field) {
            if (empty($cfg[$field])) throw new \Exception("阿里云OSS配置不完整");
        }
        $endpoint = preg_replace("#^https?://#i", "", rtrim(strval($cfg["endpoint"]), "/"));
        $client = new OssClient($cfg["accessKeyId"], $cfg["accessKeySecret"], $endpoint);
        $headers = [];
        if ($mime !== "") $headers["Content-Type"] = $mime;
        $options = $headers ? ["headers" => $headers] : [];
        $client->uploadFile($cfg["bucket"], $key, $absolute, $options);
        if (!empty($cfg["domainName"])) {
            $url = rtrim($cfg["domainName"], "/") . "/" . ltrim($key, "/");
        } else {
            $url = $client->signUrl($cfg["bucket"], $key, 315360000);
            if (strpos($url, "http://") === 0) $url = "https://" . substr($url, 7);
        }
        return ["file_path" => $key, "oss_path" => $url];
    }

    protected function uploadQcloud($absolute, $key)
    {
        $cfg = AppScopedConfig::oss($this->appid, "QCloudOSS");
        foreach (["SecretId", "SecretKey", "region", "bucket"] as $field) {
            if (empty($cfg[$field])) throw new \Exception("腾讯云OSS配置不完整");
        }
        $client = new QCloudClient([
            "region" => $cfg["region"],
            "schema" => "https",
            "credentials" => ["secretId" => $cfg["SecretId"], "secretKey" => $cfg["SecretKey"]],
        ]);
        $fp = fopen($absolute, "rb");
        if (!$fp) throw new \Exception("本地文件读取失败");
        $result = $client->upload($cfg["bucket"], $key, $fp);
        if (is_resource($fp)) fclose($fp);
        if (!empty($cfg["domainName"])) {
            $url = rtrim($cfg["domainName"], "/") . "/" . ltrim($key, "/");
        } else {
            $location = isset($result["Location"]) ? $result["Location"] : "";
            $url = $location !== "" ? "https://" . preg_replace("#^https?://#i", "", $location) : $client->getObjectUrl($cfg["bucket"], $key, "+10 years");
        }
        return ["file_path" => $key, "oss_path" => $url];
    }

    protected function uploadUpyun($absolute, $key)
    {
        $cfg = AppScopedConfig::oss($this->appid, "UpYunOSS");
        foreach (["ServiceName", "OperatorName", "OperatorPwd", "domainName"] as $field) {
            if (empty($cfg[$field])) throw new \Exception("又拍云OSS配置不完整");
        }
        if (!class_exists("\\Upyun\\Config") || !class_exists("\\Upyun\\Upyun")) {
            throw new \Exception("又拍云SDK未安装");
        }
        $serviceConfig = new \Upyun\Config($cfg["ServiceName"], $cfg["OperatorName"], $cfg["OperatorPwd"]);
        $serviceConfig->setUploadType("BLOCK_PARALLEL");
        $client = new \Upyun\Upyun($serviceConfig);
        $fp = fopen($absolute, "rb");
        if (!$fp) throw new \Exception("本地文件读取失败");
        $client->write($key, $fp);
        if (is_resource($fp)) fclose($fp);
        return ["file_path" => $key, "oss_path" => rtrim($cfg["domainName"], "/") . "/" . ltrim($key, "/")];
    }

    protected function uploadQiniu($absolute, $key, $mime)
    {
        $cfg = AppScopedConfig::oss($this->appid, "QiniuOSS");
        foreach (["Access_Key", "Secret_Key", "bucket", "domainName"] as $field) {
            if (empty($cfg[$field])) throw new \Exception("七牛云OSS配置不完整");
        }
        $auth = new QiniuAuth($cfg["Access_Key"], $cfg["Secret_Key"]);
        $token = $auth->uploadToken($cfg["bucket"]);
        $uploadMgr = new QiniuUploadManager();
        list($ret, $err) = $uploadMgr->putFile($token, $key, $absolute, null, $mime ?: "application/octet-stream", true, null, "v2");
        if ($err !== null) throw new \Exception("七牛云上传失败");
        $base = rtrim($cfg["domainName"], "/") . "/" . ltrim($key, "/");
        $url = $auth->privateDownloadUrl($base, 315360000);
        return ["file_path" => $key, "oss_path" => $url];
    }

    protected function downloadUrl($row, $key)
    {
        $type = intval(isset($row["oss_type"]) ? $row["oss_type"] : 0);
        $raw = strval(isset($row["filePath"]) ? $row["filePath"] : "");
        if ($type === 1) return $this->aliyunUrl($key, $raw);
        if ($type === 2) return $this->qcloudUrl($key, $raw);
        if ($type === 3) return $this->upyunUrl($key, $raw);
        if ($type === 4) return $this->qiniuUrl($key, $raw);
        return $raw;
    }

    protected function aliyunUrl($key, $fallback)
    {
        $cfg = AppScopedConfig::oss($this->appid, "alibabaOss");
        if (!empty($cfg["accessKeyId"]) && !empty($cfg["accessKeySecret"]) && !empty($cfg["endpoint"]) && !empty($cfg["bucket"])) {
            $endpoint = preg_replace("#^https?://#i", "", rtrim(strval($cfg["endpoint"]), "/"));
            $client = new OssClient($cfg["accessKeyId"], $cfg["accessKeySecret"], $endpoint);
            $url = $client->signUrl($cfg["bucket"], $key, 3600);
            return strpos($url, "http://") === 0 ? "https://" . substr($url, 7) : $url;
        }
        return $fallback;
    }

    protected function qcloudUrl($key, $fallback)
    {
        $cfg = AppScopedConfig::oss($this->appid, "QCloudOSS");
        if (!empty($cfg["SecretId"]) && !empty($cfg["SecretKey"]) && !empty($cfg["region"]) && !empty($cfg["bucket"])) {
            $client = new QCloudClient([
                "region" => $cfg["region"],
                "schema" => "https",
                "credentials" => ["secretId" => $cfg["SecretId"], "secretKey" => $cfg["SecretKey"]],
            ]);
            return $client->getObjectUrl($cfg["bucket"], $key, "+60 minutes");
        }
        return $fallback;
    }

    protected function upyunUrl($key, $fallback)
    {
        $cfg = AppScopedConfig::oss($this->appid, "UpYunOSS");
        if (!empty($cfg["domainName"])) return rtrim($cfg["domainName"], "/") . "/" . ltrim($key, "/");
        return $fallback;
    }

    protected function qiniuUrl($key, $fallback)
    {
        $cfg = AppScopedConfig::oss($this->appid, "QiniuOSS");
        if (!empty($cfg["domainName"])) {
            $base = rtrim($cfg["domainName"], "/") . "/" . ltrim($key, "/");
            if (!empty($cfg["Access_Key"]) && !empty($cfg["Secret_Key"])) {
                $auth = new QiniuAuth($cfg["Access_Key"], $cfg["Secret_Key"]);
                return $auth->privateDownloadUrl($base, 3600);
            }
            return $base;
        }
        return $fallback;
    }

    protected function downloadToFile($url, $absolute)
    {
        $url = trim(strval($url));
        if ($url === "") return false;
        $fp = fopen($absolute, "wb");
        if (!$fp) return false;
        $ch = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_FILE => $fp,
            CURLOPT_FOLLOWLOCATION => true,
            CURLOPT_TIMEOUT => 120,
            CURLOPT_CONNECTTIMEOUT => 15,
            CURLOPT_SSL_VERIFYPEER => false,
            CURLOPT_SSL_VERIFYHOST => false,
            CURLOPT_USERAGENT => "BlinCloudStorageMigrator/1.0",
        ]);
        $ok = curl_exec($ch);
        $code = intval(curl_getinfo($ch, CURLINFO_HTTP_CODE));
        $err = curl_error($ch);
        curl_close($ch);
        fclose($fp);
        if (!$ok || $code < 200 || $code >= 300 || !is_file($absolute) || filesize($absolute) <= 0) {
            @unlink($absolute);
            $this->log("download failed code={$code} err={$err} url=" . substr($url, 0, 160));
            return false;
        }
        return true;
    }

    protected function replaceUrlVariants($oldUrl, $newUrl)
    {
        $this->replaceReferences($oldUrl, $newUrl);
        $this->replaceReferences($this->stripQuery($oldUrl), $newUrl);
        $this->replaceReferences(str_replace("/", "\\/", $oldUrl), str_replace("/", "\\/", $newUrl));
        $this->replaceReferences(str_replace("/", "\\/", $this->stripQuery($oldUrl)), str_replace("/", "\\/", $newUrl));
    }

    protected function replaceReferences($old, $new)
    {
        $old = trim(strval($old));
        if ($old === "" || $old === $new) return;
        foreach ($this->tables as $table) {
            try {
                $columns = Db::query("SHOW COLUMNS FROM `" . config("database.prefix") . $table . "`");
            } catch (\Throwable $th) {
                continue;
            }
            foreach ($columns as $column) {
                $field = isset($column["Field"]) ? $column["Field"] : "";
                $type = strtolower(isset($column["Type"]) ? $column["Type"] : "");
                if ($field === "" || !$this->isTextColumn($type)) continue;
                try {
                    Db::execute(
                        "UPDATE `" . config("database.prefix") . $table . "` SET `" . $field . "` = REPLACE(`" . $field . "`, ?, ?) WHERE `appid` = ? AND `" . $field . "` LIKE ?",
                        [$old, $new, $this->appid, "%" . $old . "%"]
                    );
                } catch (\Throwable $th) {
                    try {
                        Db::execute(
                            "UPDATE `" . config("database.prefix") . $table . "` SET `" . $field . "` = REPLACE(`" . $field . "`, ?, ?) WHERE `" . $field . "` LIKE ?",
                            [$old, $new, "%" . $old . "%"]
                        );
                    } catch (\Throwable $ignore) {}
                }
            }
        }
    }

    protected function isTextColumn($type)
    {
        return strpos($type, "char") !== false || strpos($type, "text") !== false || strpos($type, "json") !== false;
    }

    protected function stripQuery($url)
    {
        $parts = parse_url(strval($url));
        if (!$parts || empty($parts["scheme"]) || empty($parts["host"])) return strval($url);
        $path = isset($parts["path"]) ? $parts["path"] : "";
        return $parts["scheme"] . "://" . $parts["host"] . $path;
    }

    protected function keyFromUrl($url)
    {
        $path = parse_url(strval($url), PHP_URL_PATH);
        return $this->cleanKey($path ?: "");
    }

    protected function cleanKey($key)
    {
        $key = ltrim(strval($key), "/");
        $key = preg_replace("#^public/#", "", $key);
        return preg_replace("#\\.\\.+#", "", $key);
    }

    protected function localRelativeFromRow($row)
    {
        $candidates = [
            isset($row["key"]) ? $row["key"] : "",
            $this->keyFromUrl(isset($row["filePath"]) ? $row["filePath"] : ""),
        ];
        foreach ($candidates as $candidate) {
            $relative = $this->localRelativePath($candidate, isset($row["name"]) ? $row["name"] : "");
            if ($relative !== "" && is_file($this->publicPath . $relative)) return $relative;
        }
        return $this->localRelativePath(reset($candidates), isset($row["name"]) ? $row["name"] : "");
    }

    protected function localRelativePath($key, $name)
    {
        $key = $this->cleanKey($key);
        if ($key === "") {
            $ext = pathinfo(strval($name), PATHINFO_EXTENSION);
            $key = "uploads/" . date("Ymd") . "/" . date("His") . "_" . bin2hex(random_bytes(6)) . ($ext ? "." . $ext : "");
        }
        if (strpos($key, "uploads/") !== 0) $key = "uploads/" . $key;
        return $key;
    }

    protected function cloudKeyFromLocal($relative, $name)
    {
        $relative = $this->localRelativePath($relative, $name);
        if (strpos($relative, "uploads/") === 0) return $relative;
        return "uploads/" . ltrim($relative, "/");
    }

    protected function mimeType($absolute, $fallback = "")
    {
        $fallback = trim(strval($fallback));
        if ($fallback !== "") return $fallback;
        if (function_exists("mime_content_type")) {
            $mime = @mime_content_type($absolute);
            if ($mime) return $mime;
        }
        return "application/octet-stream";
    }

    protected function normalizeLimit($limit)
    {
        return max(1, min(200, intval($limit)));
    }

    protected function ensureDir($dir)
    {
        if (!is_dir($dir)) @mkdir($dir, 0755, true);
    }

    protected function log($message)
    {
        $this->logs[] = $message;
        @file_put_contents(Env::get("runtime_path") . "log/cloud_storage_migration.log", "[" . date("Y-m-d H:i:s") . "] appid=" . $this->appid . " " . $message . PHP_EOL, FILE_APPEND);
    }
}
'''

UPYUN_COMPAT = r'''<?php

require_once __DIR__ . "/UpYunOss.php";
'''


def backup(path):
    if not path.exists():
        return
    stamp = datetime.now().strftime("%Y%m%d%H%M%S")
    shutil.copy2(path, path.with_name(f"{path.name}.bak_cloud_migration_{stamp}"))


def replace_once(source, old, new):
    if new in source:
        return source
    if old not in source:
        raise RuntimeError("missing patch target")
    return source.replace(old, new, 1)


def patch_no_need_right(source):
    match = re.search(r"public \$no_need_right\s*=\s*\[(.*?)\];", source, re.S)
    if not match:
        return source
    existing = match.group(1)
    names = re.findall(r"'([^']+)'|\"([^\"]+)\"", existing)
    values = [a or b for a, b in names]
    for value in [
        "sendEmail",
        "sendAlibabaSample",
        "migrateCloudStorageToLocal",
        "migratecloudstoragetolocal",
        "migrateLocalStorageToCloud",
        "migratelocalstoragetocloud",
    ]:
        if value not in values:
            values.append(value)
    replacement = "public $no_need_right = [" + ", ".join(f"'{value}'" for value in values) + "];"
    return source[: match.start()] + replacement + source[match.end() :]


def replace_method(source, name, body):
    pattern = re.compile(r"\n\s*public function " + re.escape(name) + r"\s*\([^)]*\)\s*\{", re.M)
    match = pattern.search(source)
    if not match:
        return source
    start = match.start()
    brace = source.find("{", match.end() - 1)
    depth = 0
    end = brace
    for index in range(brace, len(source)):
        char = source[index]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                end = index + 1
                break
    return source[:start] + "\n" + body.rstrip() + "\n" + source[end:]


def remove_method(source, name):
    pattern = re.compile(r"\n\s*public function " + re.escape(name) + r"\s*\([^)]*\)\s*\{", re.M)
    updated = source
    while True:
        match = pattern.search(updated)
        if not match:
            return updated
        start = match.start()
        brace = updated.find("{", match.end() - 1)
        depth = 0
        end = brace
        for index in range(brace, len(updated)):
            char = updated[index]
            if char == "{":
                depth += 1
            elif char == "}":
                depth -= 1
                if depth == 0:
                    end = index + 1
                    break
        updated = updated[:start] + "\n" + updated[end:]


def ensure_before(source, marker, insert):
    if insert.strip() in source:
        return source
    if marker not in source:
        raise RuntimeError("missing insert marker")
    return source.replace(marker, insert.rstrip() + "\n\n" + marker, 1)


def patch_system():
    source = SYSTEM.read_text(encoding="utf-8", errors="ignore")
    updated = source
    updated = replace_once(
        updated,
        "use app\\common\\tool\\AlibabaCloudOSS;\n",
        "use app\\common\\tool\\AlibabaCloudOSS;\nuse app\\common\\tool\\CloudStorageMigrator;\n",
    )
    updated = patch_no_need_right(updated)
    upload_body = '''    public function upload()
    {
        $appid = $this->blinConfigAppId();
        if (request()->isAjax()) {
            $oldUpload = $this->blinAppJsonConfig($appid, "upload_configuration", config('upload.'));
            $data = [
                'file_extension' => input("post.file_extension"),
                'file_path' => input("post.file_path"),
                'file_size' => input("post.file_size"),
                'upload_space' => input("post.upload_space"),
                'save_local' => input("post.save_local"),
            ];
            $oldSpace = intval(isset($oldUpload["upload_space"]) ? $oldUpload["upload_space"] : 0);
            $newSpace = intval($data["upload_space"]);
            if ($oldSpace !== 0 && $newSpace === 0) {
                $migrator = new CloudStorageMigrator($appid);
                $summary = $migrator->migrate(50);
                if (intval($summary["failed"]) > 0 || intval($summary["remaining"]) > 0) {
                    $this->error("云端文件迁移未完成，已暂缓切换本地，请点击下方迁移按钮继续处理");
                }
            } elseif ($oldSpace === 0 && $newSpace !== 0) {
                $migrator = new CloudStorageMigrator($appid);
                $summary = $migrator->migrateLocalToCloud($newSpace, 50);
                if (intval($summary["failed"]) > 0 || intval($summary["remaining"]) > 0) {
                    $this->error("本地文件迁移未完成，已暂缓切换OSS，请点击下方迁移按钮继续处理");
                }
            }
            $this->blinSaveAppJsonConfig($appid, "upload_configuration", $data);
            $this->success('修改成功');
        }
        $upload_info = $this->blinAppJsonConfig($appid, "upload_configuration", config('upload.'));
        $cloud_file_count = Db::name("file")->where("appid", $appid)->where("oss_type", ">", 0)->count();
        $local_file_count = Db::name("file")->where("appid", $appid)->where("oss_type", 0)->count();
        $other_info = $this->blinOssConfig($appid);
        return view('', [
            'upload_info' => $upload_info,
            'other_info' => $other_info,
            'apps' => $this->blinConfigAppList(),
            'current_appid' => $appid,
            'cloud_file_count' => $cloud_file_count,
            'local_file_count' => $local_file_count,
        ]);
    }'''
    updated = replace_method(updated, "upload", upload_body)
    methods = '''    public function migrateCloudStorageToLocal()
    {
        $appid = $this->blinConfigAppId();
        $limit = intval(input("post.limit") ?: input("get.limit") ?: 50);
        $migrator = new CloudStorageMigrator($appid);
        $summary = $migrator->migrate($limit);
        $this->success("迁移完成：成功" . intval($summary["success"]) . "个，失败" . intval($summary["failed"]) . "个，剩余" . intval($summary["remaining"]) . "个", "", $summary);
    }

    public function migrateLocalStorageToCloud()
    {
        $appid = $this->blinConfigAppId();
        $limit = intval(input("post.limit") ?: input("get.limit") ?: 50);
        $targetSpace = intval(input("post.target_space") ?: input("get.target_space") ?: 0);
        $migrator = new CloudStorageMigrator($appid);
        $summary = $migrator->migrateLocalToCloud($targetSpace, $limit);
        $this->success("迁移完成：成功" . intval($summary["success"]) . "个，失败" . intval($summary["failed"]) . "个，剩余" . intval($summary["remaining"]) . "个", "", $summary);
    }'''
    updated = remove_method(updated, "migrateCloudStorageToLocal")
    updated = remove_method(updated, "migrateLocalStorageToCloud")
    updated = ensure_before(updated, "    //阿里云oss配置", methods)
    if updated != source:
        backup(SYSTEM)
        SYSTEM.write_text(updated, encoding="utf-8")


def patch_view():
    source = UPLOAD_VIEW.read_text(encoding="utf-8", errors="ignore")
    updated = source

    block = '''                        <div class="d-flex flex-wrap gap-2 align-items-center">
                            <button type="button" class="btn btn-primary me-1" id="submit_data">确 定</button>
                            <button type="button" class="btn btn-secondary" id="migrateCloudStorageToLocal">迁移云端文件到本地</button>
                            <button type="button" class="btn btn-secondary" id="migrateLocalStorageToCloud">迁移本地文件到当前OSS</button>
                            <span class="text-muted">云端待迁移：{$cloud_file_count}</span>
                            <span class="text-muted">本地待迁移：{$local_file_count}</span>
                        </div>'''
    updated = re.sub(
        r'''(?s)\s*<div(?: class="d-flex flex-wrap gap-2 align-items-center")?>\s*
                            <button type="button" class="btn btn-primary me-1" id="submit_data">确 定</button>.*?
                        </div>''',
        "\n" + block,
        updated,
        count=1,
    )

    if "$(\"#migrateCloudStorageToLocal\").click" not in updated:
        marker = '''    //阿里云oss
    $("#saveAlibabaCloudOSS").click(function () {
'''
        handlers = '''    function runStorageMigration(url, payload) {
        var l = $('body').lyearloading({
            opacity: 0.2,
            spinnerSize: 'lg'
        });
        $.ajax({
            url: url,
            type: "post",
            data: payload,
            dataType: "json",
            success: function (res) {
                l.destroy();
                if (res.code == 1) {
                    notify.success(res.msg, function () {
                        window.location.reload();
                    }, 1200);
                } else {
                    notify.error(res.msg);
                }
            },
            error: function (res) {
                l.destroy();
                notify.error(res.msg || '迁移失败');
            }
        });
    }

    $("#migrateCloudStorageToLocal").click(function () {
        runStorageMigration("{:url('migrateCloudStorageToLocal')}", {appid: "{$current_appid}", limit: 50});
    });

    $("#migrateLocalStorageToCloud").click(function () {
        runStorageMigration("{:url('migrateLocalStorageToCloud')}", {
            appid: "{$current_appid}",
            limit: 50,
            target_space: $("select[name='upload_space']").val()
        });
    });

    //阿里云oss
    $("#saveAlibabaCloudOSS").click(function () {
'''
        updated = replace_once(updated, marker, handlers)
    else:
        if "$(\"#migrateLocalStorageToCloud\").click" not in updated:
            insert = '''

    $("#migrateLocalStorageToCloud").click(function () {
        var l = $('body').lyearloading({
            opacity: 0.2,
            spinnerSize: 'lg'
        });
        $.ajax({
            url: "{:url('migrateLocalStorageToCloud')}",
            type: "post",
            data: {appid: "{$current_appid}", limit: 50, target_space: $("select[name='upload_space']").val()},
            dataType: "json",
            success: function (res) {
                l.destroy();
                if (res.code == 1) {
                    notify.success(res.msg, function () {
                        window.location.reload();
                    }, 1200);
                } else {
                    notify.error(res.msg);
                }
            },
            error: function (res) {
                l.destroy();
                notify.error(res.msg || '迁移失败');
            }
        });
    });
'''
            updated = updated.replace("    //阿里云oss\n", insert + "\n    //阿里云oss\n", 1)

    if updated != source:
        backup(UPLOAD_VIEW)
        UPLOAD_VIEW.write_text(updated, encoding="utf-8")


def main():
    TOOL_DIR.mkdir(parents=True, exist_ok=True)
    migrator_path = TOOL_DIR / "CloudStorageMigrator.php"
    if (migrator_path.read_text(encoding="utf-8", errors="ignore") if migrator_path.exists() else "") != MIGRATOR:
        backup(migrator_path)
        migrator_path.write_text(MIGRATOR, encoding="utf-8")
    upyun_compat_path = TOOL_DIR / "UpYunOSS.php"
    if (upyun_compat_path.read_text(encoding="utf-8", errors="ignore") if upyun_compat_path.exists() else "") != UPYUN_COMPAT:
        backup(upyun_compat_path)
        upyun_compat_path.write_text(UPYUN_COMPAT, encoding="utf-8")
    patch_system()
    patch_view()
    print("PATCHED_BIDIRECTIONAL_CLOUD_STORAGE_MIGRATION")


if __name__ == "__main__":
    main()
