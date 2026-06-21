#!/usr/bin/env python3
"""Fix Aliyun OSS upload class loading and public media URLs."""

from datetime import datetime
from pathlib import Path
import os
import shutil


ROOT = Path(os.environ.get("BLIN_ROOT", "/www/wwwroot/blinlin"))
TOOL_DIR = ROOT / "application/common/tool"

OSS_CLASS = r'''<?php

namespace app\common\tool;

use OSS\Core\OssException;
use OSS\OssClient;
use think\facade\Env;

class AlibabaCloudOSS
{
    protected $AlibabaOss = [];
    protected $client;
    protected $appid = 0;

    public function __construct($appid = 0)
    {
        $this->appid = AppScopedConfig::appid($appid);
        $this->getAlibabaOssCache();
        $this->getClient();
    }

    public function getAlibabaOssCache()
    {
        $this->AlibabaOss = AppScopedConfig::oss($this->appid, "alibabaOss");
        return $this->AlibabaOss;
    }

    protected function configValue($key)
    {
        return trim(strval(isset($this->AlibabaOss[$key]) ? $this->AlibabaOss[$key] : ""));
    }

    protected function normalizeEndpoint($endpoint)
    {
        $endpoint = trim(strval($endpoint));
        if ($endpoint === "") return "";
        return preg_replace("#^https?://#i", "", rtrim($endpoint, "/"));
    }

    protected function joinDomain($domain, $filename)
    {
        $domain = trim(strval($domain));
        if ($domain === "") return "";
        if (!preg_match("#^https?://#i", $domain)) {
            $domain = "https://" . $domain;
        }
        return rtrim($domain, "/") . "/" . ltrim($filename, "/");
    }

    protected function logOssError($message)
    {
        $line = "[" . date("Y-m-d H:i:s") . "] appid=" . $this->appid . " " . $message . PHP_EOL;
        @file_put_contents(Env::get("runtime_path") . "log/aliyun_oss.log", $line, FILE_APPEND);
    }

    public function getClient()
    {
        $accessKeyId = $this->configValue("accessKeyId");
        $accessKeySecret = $this->configValue("accessKeySecret");
        $endpoint = $this->normalizeEndpoint($this->configValue("endpoint"));
        if ($accessKeyId === "" || $accessKeySecret === "" || $endpoint === "") {
            throw new \Exception("阿里云OSS配置不完整");
        }
        try {
            $this->client = new OssClient($accessKeyId, $accessKeySecret, $endpoint);
        } catch (\Exception $th) {
            $this->logOssError("init failed: " . $th->getMessage());
            throw new \Exception("oss初始化失败！");
        }
    }

    public function uploadFile($file, $path = "", $url = "")
    {
        try {
            $bucket = $this->configValue("bucket");
            if ($bucket === "") {
                throw new \Exception("阿里云OSS Bucket未配置");
            }
            $detail = $file->getInfo();
            $name = pathinfo($detail["name"]);
            $ext = strtolower(isset($name["extension"]) ? $name["extension"] : "");
            if ($ext === "") $ext = "bin";
            $basePath = trim(strval($path), "/");
            $prefix = $basePath === "" ? "uploads" : $basePath;
            $filename = $prefix . "/" . date("Ymd", time()) . "/" . date("His") . "_" . bin2hex(random_bytes(8)) . "." . $ext;
            $fileRealPath = $file->getRealPath();
            if ($url != "") {
                $filename = ltrim(strval($url), "/");
                $fileRealPath = $url;
            }
            if (!$fileRealPath || !is_file($fileRealPath)) {
                throw new \Exception("上传临时文件不存在");
            }
            $mime = isset($detail["type"]) ? trim(strval($detail["type"])) : "";
            $headers = [];
            if ($mime !== "") {
                $headers["Content-Type"] = $mime;
            }
            $options = $headers ? ["headers" => $headers] : [];
            $this->client->uploadFile($bucket, $filename, $fileRealPath, $options);
            $oss_path = $this->client->signUrl($bucket, $filename, 315360000);
            if (strpos($oss_path, "http://") === 0) {
                $oss_path = "https://" . substr($oss_path, 7);
            }
            $domainUrl = $this->joinDomain($this->configValue("domainName"), $filename);
            if ($domainUrl !== "") {
                $oss_path = $domainUrl;
            }
            if ($oss_path === "") {
                throw new \Exception("OSS未返回文件地址");
            }
            return ["file_path" => $filename, "oss_path" => $oss_path];
        } catch (OssException $e) {
            $this->logOssError("upload failed: " . $e->getMessage());
            throw new \Exception("上传文件失败，请检查OSS配置或Bucket权限");
        } catch (\Exception $e) {
            $this->logOssError("upload failed: " . $e->getMessage());
            throw $e;
        }
    }

    public function deleteFile($object)
    {
        try {
            $this->client->deleteObject($this->configValue("bucket"), $object);
            return true;
        } catch (OssException $e) {
            $this->logOssError("delete failed: " . $e->getMessage());
            throw new \Exception("删除失败，请检查OSS配置或Bucket权限");
        }
    }
}
'''


def backup(path: Path) -> None:
    if not path.exists():
        return
    stamp = datetime.now().strftime("%Y%m%d%H%M%S")
    shutil.copy2(path, path.with_name(f"{path.name}.bak_aliyun_oss_{stamp}"))


def write_class(path: Path) -> None:
    current = path.read_text(encoding="utf-8", errors="ignore") if path.exists() else ""
    if current == OSS_CLASS:
        return
    backup(path)
    path.write_text(OSS_CLASS, encoding="utf-8")


def main() -> None:
    TOOL_DIR.mkdir(parents=True, exist_ok=True)
    write_class(TOOL_DIR / "AlibabaCloudOSS.php")
    write_class(TOOL_DIR / "alibabaCloudOSS.php")
    print("PATCHED_ALIYUN_OSS_UPLOAD")


if __name__ == "__main__":
    main()
