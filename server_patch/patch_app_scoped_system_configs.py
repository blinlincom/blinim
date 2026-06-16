#!/usr/bin/env python3
"""Make email, SMS and upload settings application-scoped."""

from datetime import datetime
from pathlib import Path
import os
import re
import shutil
import subprocess


ROOT = Path("/www/wwwroot/blinlin")
ADMIN_SYSTEM = ROOT / "application/admin/controller/System.php"
ADMIN_INDEX = ROOT / "application/admin/controller/Index.php"
API = ROOT / "application/api/controller/Api.php"
BASE = ROOT / "application/api/controller/BaseController.php"
APP = ROOT / "application/admin/controller/App.php"
EMAIL_TOOL = ROOT / "application/common/tool/Email.php"
SMS_TOOL = ROOT / "application/common/tool/AlibabaSample.php"
UPLOAD_TOOL = ROOT / "application/common/tool/Upload.php"
APP_CONFIG_TOOL = ROOT / "application/common/tool/AppScopedConfig.php"
ALIYUN_OSS = ROOT / "application/common/tool/alibabaCloudOSS.php"
QCLOUD_OSS = ROOT / "application/common/tool/QCloudOSS.php"
UPYUN_OSS = ROOT / "application/common/tool/UpYunOss.php"
QINIU_OSS = ROOT / "application/common/tool/QiniuOSS.php"
EMAIL_VIEW = ROOT / "application/admin/view/system/email.html"
SMS_VIEW = ROOT / "application/admin/view/system/sms_config.html"
UPLOAD_VIEW = ROOT / "application/admin/view/system/upload.html"


def backup(path: Path, suffix: str) -> None:
    target = path.with_name(
        f"{path.name}.bak_{suffix}_{datetime.now().strftime('%Y%m%d%H%M%S')}"
    )
    shutil.copy2(path, target)
    print("BACKUP", target)


def save(path: Path, original: str, source: str, suffix: str) -> bool:
    if source == original:
        print("NO_CHANGE", path)
        return False
    backup(path, suffix)
    path.write_text(source)
    print("PATCHED", path)
    return True


def write_file(path: Path, source: str, suffix: str) -> bool:
    original = path.read_text(errors="ignore") if path.exists() else ""
    if original == source:
        print("NO_CHANGE", path)
        return False
    if path.exists():
        backup(path, suffix)
    path.write_text(source)
    print("WRITTEN", path)
    return True


def replace_once(source: str, old: str, new: str, label: str) -> str:
    if old not in source:
        raise SystemExit(f"{label}_MARKER_NOT_FOUND")
    return source.replace(old, new, 1)


def replace_method(source: str, start_marker: str, next_marker: str, new_block: str, label: str) -> str:
    start = source.find(start_marker)
    if start < 0:
        raise SystemExit(f"{label}_START_NOT_FOUND")
    end = source.find(next_marker, start + len(start_marker))
    if end < 0:
        raise SystemExit(f"{label}_END_NOT_FOUND")
    return source[:start] + new_block + "\n\n    " + source[end:]


def db_config():
    values = {
        "hostname": "127.0.0.1",
        "database": "blinlin",
        "username": "root",
        "password": "",
        "hostport": "3306",
    }
    env_path = ROOT / ".env"
    section = ""
    if not env_path.exists():
        return values
    for raw in env_path.read_text(errors="ignore").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or line.startswith(";"):
            continue
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1].strip().lower()
            continue
        if section != "database" or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip().lower()
        value = value.strip().strip('"').strip("'")
        if key in values:
            values[key] = value
    return values


def mysql(sql: str, ignore=()):
    config = db_config()
    env = os.environ.copy()
    env["MYSQL_PWD"] = config["password"]
    result = subprocess.run(
        [
            "mysql",
            f"-h{config['hostname']}",
            f"-u{config['username']}",
            f"-P{config.get('hostport') or '3306'}",
            config["database"],
            "-e",
            sql,
        ],
        universal_newlines=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
        check=False,
    )
    if result.returncode != 0:
        err = result.stderr.strip()
        if any(item in err for item in ignore):
            print("MYSQL_IGNORE", err)
            return ""
        raise SystemExit(err)
    if result.stdout.strip():
        print(result.stdout.strip())
    return result.stdout


def patch_database():
    for sql in [
        "ALTER TABLE `mr_app` ADD COLUMN `system_configuration` text DEFAULT NULL",
        "ALTER TABLE `mr_app` ADD COLUMN `email_configuration` text DEFAULT NULL",
        "ALTER TABLE `mr_app` ADD COLUMN `sms_configuration` text DEFAULT NULL",
        "ALTER TABLE `mr_app` ADD COLUMN `upload_configuration` text DEFAULT NULL",
        "ALTER TABLE `mr_app` ADD COLUMN `oss_configuration` text DEFAULT NULL",
        "ALTER TABLE `mr_file` ADD COLUMN `appid` bigint(20) NOT NULL DEFAULT 0",
    ]:
        mysql(sql, ("Duplicate column name",))


APP_SCOPED_CONFIG = r'''<?php

namespace app\common\tool;

use think\Db;

class AppScopedConfig
{
    public static function appid($appid = 0)
    {
        $appid = intval($appid);
        if ($appid > 0) return $appid;
        try {
            $appid = intval(request()->param("appid"));
        } catch (\Throwable $th) {
            $appid = 0;
        }
        return $appid;
    }

    public static function decode($raw)
    {
        if (is_array($raw)) return $raw;
        $raw = trim(strval($raw));
        if ($raw === "") return [];
        $value = json_decode($raw, true);
        return is_array($value) ? $value : [];
    }

    public static function globalRow($name)
    {
        try {
            $row = Db::name("config")->where("name", $name)->find();
            if (!$row || !isset($row["value"])) return [];
            return self::decode($row["value"]);
        } catch (\Throwable $th) {
            return [];
        }
    }

    public static function appColumn($appid, $column)
    {
        $appid = self::appid($appid);
        if ($appid <= 0) return [];
        try {
            $row = Db::name("app")->where("appid", $appid)->field($column)->find();
            if (!$row || !isset($row[$column])) return [];
            return self::decode($row[$column]);
        } catch (\Throwable $th) {
            return [];
        }
    }

    public static function system($appid = 0)
    {
        $global = config("system.");
        if (!is_array($global)) $global = [];
        $defaults = [
            "email_code_time" => isset($global["email_code_time"]) ? $global["email_code_time"] : 300,
            "email_code_interval_time" => isset($global["email_code_interval_time"]) ? $global["email_code_interval_time"] : 60,
            "phone_code_time" => isset($global["phone_code_time"]) ? $global["phone_code_time"] : 300,
            "phone_code_interval_time" => isset($global["phone_code_interval_time"]) ? $global["phone_code_interval_time"] : 60,
            "maximum_number" => isset($global["maximum_number"]) ? $global["maximum_number"] : 0,
        ];
        return array_merge($defaults, self::appColumn($appid, "system_configuration"));
    }

    public static function systemValue($appid, $key, $default = null)
    {
        $config = self::system($appid);
        return isset($config[$key]) && $config[$key] !== "" ? $config[$key] : $default;
    }

    public static function email($appid = 0)
    {
        return array_merge(self::globalRow("email"), self::appColumn($appid, "email_configuration"));
    }

    public static function sms($appid = 0)
    {
        return array_merge(self::globalRow("AlibabaSample"), self::appColumn($appid, "sms_configuration"));
    }

    public static function upload($appid = 0)
    {
        $global = config("upload.");
        if (!is_array($global)) $global = [];
        return array_merge($global, self::appColumn($appid, "upload_configuration"));
    }

    public static function oss($appid = 0, $name = "")
    {
        $global = $name === "" ? [] : self::globalRow($name);
        $all = self::appColumn($appid, "oss_configuration");
        $local = isset($all[$name]) && is_array($all[$name]) ? $all[$name] : [];
        return array_merge($global, $local);
    }
}
'''


EMAIL_TOOL_SOURCE = r'''<?php

namespace app\common\tool;

use PHPMailer\PHPMailer\PHPMailer;

class Email
{
    protected $toEmail = null;
    protected $subject = null;
    protected $body = null;
    protected $mailCache = [];
    protected $appid = 0;

    public function __construct($toEmail = '', $appid = 0)
    {
        $this->toEmail = $toEmail;
        $this->appid = AppScopedConfig::appid($appid);
        $this->getEmailCache();
    }

    public function getEmailCache()
    {
        $this->mailCache = AppScopedConfig::email($this->appid);
        return $this->mailCache;
    }

    public function setFrom($from)
    {
        $this->mailCache['fromName'] = $from;
    }

    public function setSubject($subject)
    {
        $this->subject = $subject;
    }

    public function setBody($body)
    {
        $this->body = $body;
    }

    public function send()
    {
        if ($this->toEmail == null) return "邮箱不能为空！";
        foreach (["host", "username", "password", "port"] as $key) {
            if (!isset($this->mailCache[$key]) || trim(strval($this->mailCache[$key])) === "") {
                return "邮箱配置信息不完整！";
            }
        }
        $subject = $this->subject != null ? $this->subject : (isset($this->mailCache['fromName']) ? $this->mailCache['fromName'] : '');
        if ($this->body == null) return "邮件内容不能为空！";
        $mail = new PHPMailer(true);
        try {
            $mail->CharSet = "UTF-8";
            $mail->isSMTP();
            $mail->SMTPAuth = true;
            $mail->Host = $this->mailCache['host'];
            $mail->Username = $this->mailCache['username'];
            $mail->Password = $this->mailCache['password'];
            $mail->SMTPSecure = 'ssl';
            $mail->Port = $this->mailCache['port'];
            $mail->setFrom($this->mailCache['username'], isset($this->mailCache['fromName']) ? $this->mailCache['fromName'] : '');
            $mail->addAddress($this->toEmail);
            $mail->isHTML(true);
            $mail->Subject = $subject;
            $mail->Body = $this->body;
            $mail->send();
            return 1;
        } catch (\Exception $e) {
            return "发送失败！";
        }
    }
}
'''


SMS_TOOL_SOURCE = r'''<?php

namespace app\common\tool;

use AlibabaCloud\SDK\Dysmsapi\V20170525\Dysmsapi;
use AlibabaCloud\SDK\Dysmsapi\V20170525\Models\SendSmsRequest;
use AlibabaCloud\Tea\Utils\Utils\RuntimeOptions;
use Darabonba\OpenApi\Models\Config;
use Exception;

class AlibabaSample
{
    protected $AlibabaSample = [];
    protected $code;
    protected $appid = 0;

    public function __construct($appid = 0)
    {
        $this->appid = AppScopedConfig::appid($appid);
        $this->getAlibabaSampleCache();
    }

    public function getAlibabaSampleCache()
    {
        $this->AlibabaSample = AppScopedConfig::sms($this->appid);
        return $this->AlibabaSample;
    }

    public function setCode($code)
    {
        $this->code = $code;
    }

    public function send($phone)
    {
        foreach (["accessKeyId", "accessKeySecret", "signName", "TemplateCode", "TemplateParam"] as $key) {
            if (!isset($this->AlibabaSample[$key]) || trim(strval($this->AlibabaSample[$key])) === "") {
                return "短信配置信息不完整！";
            }
        }
        $config = new Config([
            "accessKeyId" => $this->AlibabaSample['accessKeyId'],
            "accessKeySecret" => $this->AlibabaSample['accessKeySecret']
        ]);
        $config->endpoint = "dysmsapi.aliyuncs.com";
        $client = new Dysmsapi($config);
        try {
            $TemplateParam = ["{$this->AlibabaSample['TemplateParam']}" => $this->code];
            $sendSmsRequest = new SendSmsRequest([
                "phoneNumbers" => $phone,
                "signName" => $this->AlibabaSample['signName'],
                "templateCode" => $this->AlibabaSample['TemplateCode'],
                "templateParam" => json_encode($TemplateParam, JSON_UNESCAPED_UNICODE),
            ]);
            $result = $client->sendSmsWithOptions($sendSmsRequest, new RuntimeOptions([]));
            return $result->statusCode == '200' ? 1 : "短信发送失败！";
        } catch (Exception $error) {
            return "短信发送失败！";
        }
    }
}
'''


UPLOAD_TOOL_SOURCE = r'''<?php

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
        $this->appid = AppScopedConfig::appid($appid);
        if ($uploader_id == 0) {
            $this->uploader = 0;
            $this->uploader_id = session("admin.id");
        } else {
            $this->uploader = 1;
            $this->uploader_id = $uploader_id;
        }
        $this->upload_system = AppScopedConfig::upload($this->appid);
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
        if (!in_array($ext, explode(",", $this->upload_system["file_extension"]))) {
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
        $uploadFileAddress = $this->upload_system['upload_space'];
        $uploadPath = $this->upload_system["file_path"];
        $detail = $file->getInfo();
        if ($uploadFileAddress == 0) {
            $filePath = $this->save($file);
            $url = request()->domain() . "/" . $filePath;
            $key = $filePath;
        } else {
            $url = "";
            if ($this->upload_system["save_local"] == 0) {
                $new_file = $file;
                $url = $this->save($new_file);
            }
            if ($uploadFileAddress == 1) {
                $oss = new AlibabaCloudOSS($this->appid);
                $result = $oss->uploadFile($file, $uploadPath, $url);
            } elseif ($uploadFileAddress == 2) {
                $oss = new QCloudOSS($this->appid);
                $result = $oss->uploadFile($file, $uploadPath, $url);
            } elseif ($uploadFileAddress == 3) {
                $oss = new UpYunOSS($this->appid);
                $result = $oss->uploadFile($file, $uploadPath, $url);
            } elseif ($uploadFileAddress == 4) {
                $oss = new QiniuOSS($this->appid);
                $result = $oss->uploadFile($file, $uploadPath, $url);
            } else {
                throw new \Exception("上传空间配置错误");
            }
            if (!is_array($result)) {
                throw new \Exception($result);
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


ALIYUN_OSS_SOURCE = r'''<?php

namespace app\common\tool;

use OSS\Core\OssException;
use OSS\OssClient;

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

    public function getClient()
    {
        try {
            $this->client = new OssClient($this->AlibabaOss['accessKeyId'], $this->AlibabaOss['accessKeySecret'], $this->AlibabaOss['endpoint']);
        } catch (\Exception $th) {
            throw new \Exception("oss初始化失败！");
        }
    }

    public function uploadFile($file, $path = '', $url = '')
    {
        try {
            $detail = $file->getInfo();
            $name = pathinfo($detail["name"]);
            $ext = strtolower(isset($name["extension"]) ? $name["extension"] : "");
            $filename = $path . "/" . date("Ymd", time()) . "/" . md5(time()) . '.' . $ext;
            $fileRealPath = $file->getRealPath();
            if ($url != '') {
                $filename = $url;
                $fileRealPath = $url;
            }
            $type = explode("/", $detail["type"]);
            $options = [];
            if ($type[0] == "image") {
                $options = ['headers' => ['Content-Type' => 'image/jpg']];
            }
            $result = $this->client->uploadFile($this->AlibabaOss['bucket'], $filename, $fileRealPath, $options);
            $oss_path = $result['info']['url'];
            if (isset($this->AlibabaOss['domainName']) && $this->AlibabaOss['domainName'] != "") {
                $oss_path = $this->AlibabaOss['domainName'] . $filename;
            }
            return ["file_path" => $filename, "oss_path" => $oss_path];
        } catch (OssException $e) {
            throw new \Exception("上传文件失败！，请检查配置信息是否正确");
        }
    }

    public function deleteFile($object)
    {
        try {
            $this->client->deleteObject($this->AlibabaOss['bucket'], $object);
            return true;
        } catch (OssException $e) {
            throw new \Exception("删除失败！，请检查配置信息是否正确");
        }
    }
}
'''


QCLOUD_OSS_SOURCE = r'''<?php

namespace app\common\tool;

use Qcloud\Cos\Client;
use traits\controller\Jump;

class QCloudOSS
{
    use Jump;

    protected $QCloudOSS = [];
    protected $client;
    protected $appid = 0;

    public function __construct($appid = 0)
    {
        $this->appid = AppScopedConfig::appid($appid);
        $this->getQCloudOSSCache();
        $this->getClient();
    }

    public function getQCloudOSSCache()
    {
        $this->QCloudOSS = AppScopedConfig::oss($this->appid, "QCloudOSS");
        return $this->QCloudOSS;
    }

    public function getClient()
    {
        try {
            $this->client = new Client([
                'region' => $this->QCloudOSS['region'],
                'schema' => request()->scheme(),
                'credentials' => [
                    'secretId' => $this->QCloudOSS['SecretId'],
                    'secretKey' => $this->QCloudOSS['SecretKey'],
                ],
            ]);
        } catch (\Exception $th) {
            throw new \Exception("oss初始化失败！");
        }
    }

    public function uploadFile($file, $path = '', $url = '')
    {
        try {
            $detail = $file->getInfo();
            $name = pathinfo($detail["name"]);
            $ext = strtolower(isset($name["extension"]) ? $name["extension"] : "");
            $filename = $path . "/" . date("Ymd", time()) . "/" . md5(time()) . '.' . $ext;
            $fileRealPath = $file->getRealPath();
            if ($url != '') {
                $filename = $url;
                $fileRealPath = $url;
            }
            $result = $this->client->upload($this->QCloudOSS['bucket'], $filename, fopen($fileRealPath, 'rb'));
            $oss_path = request()->scheme() . "://" . $result['Location'];
            if (isset($this->QCloudOSS['domainName']) && $this->QCloudOSS['domainName'] != "") {
                $oss_path = $this->QCloudOSS['domainName'] . $filename;
            }
            return ["file_path" => $filename, "oss_path" => $oss_path];
        } catch (\Exception $e) {
            throw new \Exception("上传文件失败！，请检查配置信息是否正确");
        }
    }

    public function deleteFile($key)
    {
        if ($key == "") return false;
        try {
            $this->client->deleteObject(['Bucket' => $this->QCloudOSS['bucket'], 'Key' => $key]);
            return true;
        } catch (\Exception $e) {
            throw new \Exception("删除失败！，请检查配置信息是否正确");
        }
    }
}
'''


UPYUN_OSS_SOURCE = r'''<?php

namespace app\common\tool;

use Upyun\Config;
use Upyun\Upyun;

class UpYunOSS
{
    protected $UpYunOSS = [];
    protected $client;
    protected $appid = 0;

    public function __construct($appid = 0)
    {
        $this->appid = AppScopedConfig::appid($appid);
        $this->getUpYunOSSCache();
        $this->getClient();
    }

    public function getUpYunOSSCache()
    {
        $this->UpYunOSS = AppScopedConfig::oss($this->appid, "UpYunOSS");
        return $this->UpYunOSS;
    }

    public function getClient()
    {
        try {
            $serviceConfig = new Config($this->UpYunOSS['ServiceName'], $this->UpYunOSS['OperatorName'], $this->UpYunOSS['OperatorPwd']);
            $serviceConfig->setUploadType('BLOCK_PARALLEL');
            $this->client = new Upyun($serviceConfig);
        } catch (\Throwable $th) {
            throw new \Exception("oss初始化失败！");
        }
    }

    public function uploadFile($file, $path = '', $url = '')
    {
        try {
            $detail = $file->getInfo();
            $name = pathinfo($detail["name"]);
            $ext = strtolower(isset($name["extension"]) ? $name["extension"] : "");
            $filename = $path . "/" . date("Ymd", time()) . "/" . md5(time()) . '.' . $ext;
            $fileRealPath = $file->getRealPath();
            if ($url != '') {
                $filename = $url;
                $fileRealPath = $url;
            }
            $file = fopen($fileRealPath, 'r');
            $this->client->write($filename, $file);
            return ["file_path" => $filename, "oss_path" => $this->UpYunOSS['domainName'] . $filename];
        } catch (\Exception $e) {
            throw new \Exception("上传文件失败！，请检查配置信息是否正确");
        }
    }

    public function deleteFile($key)
    {
        try {
            $this->client->delete($key);
            return true;
        } catch (\Exception $e) {
            throw new \Exception("删除失败！，请检查配置信息是否正确");
        }
    }
}
'''


QINIU_OSS_SOURCE = r'''<?php

namespace app\common\tool;

use Qiniu\Auth;
use Qiniu\Storage\UploadManager;
use traits\controller\Jump;

class QiniuOSS
{
    use Jump;

    protected $QiniuOSS = [];
    protected $token;
    protected $auth;
    protected $appid = 0;

    public function __construct($appid = 0)
    {
        $this->appid = AppScopedConfig::appid($appid);
        $this->getQiniuOSSCache();
        $this->uploadToken();
    }

    public function getQiniuOSSCache()
    {
        $this->QiniuOSS = AppScopedConfig::oss($this->appid, "QiniuOSS");
        return $this->QiniuOSS;
    }

    public function uploadToken()
    {
        $this->auth = new Auth($this->QiniuOSS['Access_Key'], $this->QiniuOSS['Secret_Key']);
        $this->token = $this->auth->uploadToken($this->QiniuOSS['bucket']);
    }

    public function uploadFile($file, $path = '', $url = '')
    {
        try {
            $detail = $file->getInfo();
            $name = pathinfo($detail["name"]);
            $ext = strtolower(isset($name["extension"]) ? $name["extension"] : "");
            $filename = $path . "/" . date("Ymd", time()) . "/" . md5(time()) . '.' . $ext;
            $fileRealPath = $file->getRealPath();
            if ($url != '') {
                $filename = $url;
                $fileRealPath = $url;
            }
            $uploadMgr = new UploadManager();
            list($ret, $err) = $uploadMgr->putFile($this->token, $filename, $fileRealPath, null, 'application/octet-stream', true, null, 'v2');
            return ["file_path" => $filename, "oss_path" => $this->QiniuOSS['domainName'] . $filename];
        } catch (\Exception $e) {
            throw new \Exception("上传失败！，请检查配置信息是否正确");
        }
    }

    public function deleteFile($key)
    {
        try {
            $config = new \Qiniu\Config();
            $bucketManager = new \Qiniu\Storage\BucketManager($this->auth, $config);
            $bucketManager->delete($this->QiniuOSS["bucket"], $key);
            return true;
        } catch (\Throwable $e) {
            throw new \Exception("删除失败！，请检查配置信息是否正确");
        }
    }
}
'''


def patch_tool_classes():
    write_file(APP_CONFIG_TOOL, APP_SCOPED_CONFIG, "app_scoped_config")
    write_file(EMAIL_TOOL, EMAIL_TOOL_SOURCE, "app_scoped_email")
    write_file(SMS_TOOL, SMS_TOOL_SOURCE, "app_scoped_sms")
    write_file(UPLOAD_TOOL, UPLOAD_TOOL_SOURCE, "app_scoped_upload")
    write_file(ALIYUN_OSS, ALIYUN_OSS_SOURCE, "app_scoped_oss")
    write_file(QCLOUD_OSS, QCLOUD_OSS_SOURCE, "app_scoped_oss")
    write_file(UPYUN_OSS, UPYUN_OSS_SOURCE, "app_scoped_oss")
    write_file(QINIU_OSS, QINIU_OSS_SOURCE, "app_scoped_oss")


BASE_HELPERS = r'''
    // blin-app-scoped-system-config
    protected function blinAppSystemValue($key, $default = null)
    {
        return \app\common\tool\AppScopedConfig::systemValue($this->appid, $key, $default);
    }

    protected function blinAppUploadConfig($key = null, $default = null)
    {
        $config = \app\common\tool\AppScopedConfig::upload($this->appid);
        if ($key === null) return $config;
        return isset($config[$key]) && $config[$key] !== "" ? $config[$key] : $default;
    }

'''


def patch_base_controller():
    source = BASE.read_text(errors="ignore")
    original = source

    if '"system_configuration", "email_configuration", "sms_configuration", "upload_configuration", "oss_configuration"' not in source:
        source = replace_once(
            source,
            '''            $result["userinfo_configuration"] = json_decode($result["userinfo_configuration"], true);
            $this->appkey = $result["appkey"];''',
            '''            $result["userinfo_configuration"] = json_decode($result["userinfo_configuration"], true);
            foreach (["system_configuration", "email_configuration", "sms_configuration", "upload_configuration", "oss_configuration"] as $configField) {
                $result[$configField] = isset($result[$configField]) && $result[$configField] ? json_decode($result[$configField], true) : [];
                if (!is_array($result[$configField])) $result[$configField] = [];
            }
            $this->appkey = $result["appkey"];''',
            "base_decode_app_scoped_configs",
        )

    if "blin-app-scoped-system-config" not in source:
        source = replace_once(
            source,
            "    //更新用户在线记录\n    public function getUserLogonInfoByUsertoken",
            BASE_HELPERS + "    //更新用户在线记录\n    public function getUserLogonInfoByUsertoken",
            "base_helpers",
        )

    source = source.replace(
        '$maximum_number = config("?system.maximum_number") ? config("system.maximum_number") : 0;',
        '$maximum_number = $this->blinAppSystemValue("maximum_number", config("?system.maximum_number") ? config("system.maximum_number") : 0);',
    )

    save(BASE, original, source, "app_scoped_config")


def patch_api_controller():
    source = API.read_text(errors="ignore")
    original = source

    replacements = {
        'config("?system.phone_code_time") ? config("system.phone_code_time") : 300': '$this->blinAppSystemValue("phone_code_time", 300)',
        'config("?system.phone_code_interval_time") ? config("system.phone_code_interval_time") : 60': '$this->blinAppSystemValue("phone_code_interval_time", 60)',
        'config("?system.email_code_time") ? config("system.email_code_time") : 300': '$this->blinAppSystemValue("email_code_time", 300)',
        'config("?system.email_code_interval_time") ? config("system.email_code_interval_time") : 60': '$this->blinAppSystemValue("email_code_interval_time", 60)',
        'config("system.phone_code_time")': '$this->blinAppSystemValue("phone_code_time", 300)',
        'config("system.email_code_time")': '$this->blinAppSystemValue("email_code_time", 300)',
        'new AlibabaSample()': 'new AlibabaSample($this->appid)',
    }
    for old, new in replacements.items():
        source = source.replace(old, new)
    if '$this->blinAppUploadConfig("file_path"' not in source:
        source = source.replace(
            'config("upload.file_path")',
            '$this->blinAppUploadConfig("file_path", config("upload.file_path"))',
        )

    save(API, original, source, "app_scoped_config")


SYSTEM_HELPERS = r'''
    // blin-app-scoped-system-config
    private function blinConfigAppList()
    {
        return method_exists($this, "blinScopedAppList") ? $this->blinScopedAppList() : Db::name("app")->field("appid,appname,appicon")->order("appid", "asc")->select();
    }

    private function blinConfigAppId()
    {
        $appid = intval(input("appid") ?: input("post.appid") ?: input("get.appid"));
        $apps = $this->blinConfigAppList();
        if ($appid <= 0 && $apps) $appid = intval($apps[0]["appid"]);
        if ($appid > 0 && method_exists($this, "blinRequireApp")) $this->blinRequireApp($appid);
        return $appid;
    }

    private function blinDecodeConfig($raw)
    {
        if (is_array($raw)) return $raw;
        $value = json_decode(strval($raw), true);
        return is_array($value) ? $value : [];
    }

    private function blinGlobalConfigRow($name)
    {
        $row = Db::name("config")->where("name", $name)->find();
        return $row && isset($row["value"]) ? $this->blinDecodeConfig($row["value"]) : [];
    }

    private function blinAppJsonConfig($appid, $column, $global = [])
    {
        if ($appid <= 0) return $global;
        $row = Db::name("app")->where("appid", $appid)->field($column)->find();
        $local = $row && isset($row[$column]) ? $this->blinDecodeConfig($row[$column]) : [];
        return array_merge($global, $local);
    }

    private function blinSaveAppJsonConfig($appid, $column, $config)
    {
        if ($appid <= 0) $this->error("请先选择应用");
        if (method_exists($this, "blinRequireApp")) $this->blinRequireApp($appid);
        Db::name("app")->where("appid", $appid)->update([$column => json_encode($config, JSON_UNESCAPED_UNICODE)]);
    }

    private function blinSystemCodeConfig($appid)
    {
        $global = config("system.");
        if (!is_array($global)) $global = [];
        $base = [
            "email_code_time" => isset($global["email_code_time"]) ? $global["email_code_time"] : 300,
            "email_code_interval_time" => isset($global["email_code_interval_time"]) ? $global["email_code_interval_time"] : 60,
            "phone_code_time" => isset($global["phone_code_time"]) ? $global["phone_code_time"] : 300,
            "phone_code_interval_time" => isset($global["phone_code_interval_time"]) ? $global["phone_code_interval_time"] : 60,
            "maximum_number" => isset($global["maximum_number"]) ? $global["maximum_number"] : 0,
        ];
        return $this->blinAppJsonConfig($appid, "system_configuration", $base);
    }

    private function blinSaveSystemCodeConfig($appid, $values)
    {
        $current = $this->blinAppJsonConfig($appid, "system_configuration", []);
        foreach ($values as $key => $value) {
            $current[$key] = $value;
        }
        $this->blinSaveAppJsonConfig($appid, "system_configuration", $current);
    }

    private function blinOssConfig($appid)
    {
        $all = $this->blinAppJsonConfig($appid, "oss_configuration", []);
        foreach (["alibabaOss", "QCloudOSS", "UpYunOSS", "QiniuOSS"] as $name) {
            $global = $this->blinGlobalConfigRow($name);
            $local = isset($all[$name]) && is_array($all[$name]) ? $all[$name] : [];
            $all[$name] = array_merge($global, $local);
        }
        return $all;
    }

    private function blinSaveOssConfig($appid, $name, $config)
    {
        $all = $this->blinAppJsonConfig($appid, "oss_configuration", []);
        $all[$name] = $config;
        $this->blinSaveAppJsonConfig($appid, "oss_configuration", $all);
    }

'''


EMAIL_METHOD = r'''//邮件配置
    public function email()
    {
        $appid = $this->blinConfigAppId();
        if (request()->isAjax()) {
            $data = [
                'username' => input("post.username"),
                'password' => input("post.password"),
                'host' => input("post.host"),
                'port' => input("post.port"),
                'fromName' => input("post.fromName"),
            ];
            $this->blinSaveAppJsonConfig($appid, "email_configuration", $data);
            $this->blinSaveSystemCodeConfig($appid, [
                "email_code_time" => input("post.email_code_time"),
                "email_code_interval_time" => input("post.email_code_interval_time"),
            ]);
            $this->success("修改成功！");
        }
        $email_info_value = $this->blinAppJsonConfig($appid, "email_configuration", $this->blinGlobalConfigRow("email"));
        $system_info = $this->blinSystemCodeConfig($appid);
        $tplList = '../extend/EmailTpl/tpl.php';
        $tplList = file_exists($tplList) ? include $tplList : [];
        return view('', [
            'info' => $email_info_value,
            'tplList' => $tplList,
            'apps' => $this->blinConfigAppList(),
            'current_appid' => $appid,
            'system_info' => $system_info,
        ]);
    }

    //测试发送邮件
    public function sendEmail()
    {
        $appid = $this->blinConfigAppId();
        $toEmail = input("post.toEmail");
        $email = new Email($toEmail, $appid);
        $email->setBody("当您看到这封邮件的时候，说明您的邮箱配置已经成功！");
        $result = $email->send();
        if ($result == 1) {
            $this->success("发送成功！");
        } else {
            $this->error($result ?: "发送失败！");
        }
    }'''


UPLOAD_METHOD = r'''//上传配置
    public function upload()
    {
        $appid = $this->blinConfigAppId();
        if (request()->isAjax()) {
            $data = [
                'file_extension' => input("post.file_extension"),
                'file_path' => input("post.file_path"),
                'file_size' => input("post.file_size"),
                'upload_space' => input("post.upload_space"),
                'save_local' => input("post.save_local"),
            ];
            $this->blinSaveAppJsonConfig($appid, "upload_configuration", $data);
            $this->success('修改成功');
        }
        $upload_info = $this->blinAppJsonConfig($appid, "upload_configuration", config('upload.'));
        $other_info = $this->blinOssConfig($appid);
        return view('', [
            'upload_info' => $upload_info,
            'other_info' => $other_info,
            'apps' => $this->blinConfigAppList(),
            'current_appid' => $appid,
        ]);
    }'''


SMS_METHODS = r'''public function sms_config()
    {
        $appid = $this->blinConfigAppId();
        $other_info = [
            "AlibabaSample" => $this->blinAppJsonConfig($appid, "sms_configuration", $this->blinGlobalConfigRow("AlibabaSample")),
        ];
        return view('', [
            'other_info' => $other_info,
            'apps' => $this->blinConfigAppList(),
            'current_appid' => $appid,
            'system_info' => $this->blinSystemCodeConfig($appid),
        ]);
    }

    public function saveAlibabaSample()
    {
        $appid = $this->blinConfigAppId();
        $accessKeyId = input("post.accessKeyId");
        $accessKeySecret = input("post.accessKeySecret");
        $signName = input("post.signName");
        $TemplateCode = input("post.TemplateCode");
        $TemplateParam = input("post.TemplateParam");
        if ($accessKeyId == '' || $accessKeySecret == '' || $signName == '' || $TemplateCode == '' || $TemplateParam == '') {
            $this->error("请输入完整！");
        }
        $add_data = [
            "accessKeyId" => $accessKeyId,
            "accessKeySecret" => $accessKeySecret,
            "signName" => $signName,
            "TemplateCode" => $TemplateCode,
            "TemplateParam" => $TemplateParam,
        ];
        $this->blinSaveAppJsonConfig($appid, "sms_configuration", $add_data);
        $this->blinSaveSystemCodeConfig($appid, [
            "phone_code_time" => input("post.phone_code_time"),
            "phone_code_interval_time" => input("post.phone_code_interval_time"),
        ]);
        $this->success("修改成功！");
    }

    public function sendAlibabaSample()
    {
        $appid = $this->blinConfigAppId();
        $phone = input("post.phone");
        if ($phone == '') {
            $this->error("请输入手机号！");
        }
        $oss = new AlibabaSample($appid);
        $result = $oss->send($phone);
        if ($result == 1) {
            $this->success("发送成功！");
        } else {
            $this->error($result ?: "发送失败！");
        }
    }'''


def patch_system_controller():
    source = ADMIN_SYSTEM.read_text(errors="ignore")
    original = source

    if "blin-app-scoped-system-config" not in source:
        source = replace_once(source, "    //系统配置\n    public function system()", SYSTEM_HELPERS + "    //系统配置\n    public function system()", "system_helpers")

    source = replace_method(source, "    //邮件配置\n    public function email()", "    public function editEmailTpl()", "    " + EMAIL_METHOD, "email_method")
    source = replace_method(source, "    //上传配置\n    public function upload()", "    //阿里云oss配置", "    " + UPLOAD_METHOD, "upload_method")

    oss_replacements = {
        "saveAlibabaCloudOSS": (
            '''    //阿里云oss配置
    public function saveAlibabaCloudOSS()
    {
        $appid = $this->blinConfigAppId();
        $accessKeyId = input("post.accessKeyId");
        $accessKeySecret = input("post.accessKeySecret");
        $bucket = input("post.bucket");
        $endpoint = input("post.endpoint");
        $domainName = input("post.domainName");
        if ($accessKeyId == '' || $accessKeySecret == '' || $bucket == '' || $endpoint == '') {
            $this->error("请输入完整！");
        }
        $this->blinSaveOssConfig($appid, "alibabaOss", [
            'accessKeyId' => $accessKeyId,
            'accessKeySecret' => $accessKeySecret,
            'bucket' => $bucket,
            'endpoint' => $endpoint,
            'domainName' => $domainName
        ]);
        $this->success("修改成功！");
    }''',
            "    //腾讯云oss配置",
        ),
        "saveQCloudOSS": (
            '''    //腾讯云oss配置
    public function saveQCloudOSS()
    {
        $appid = $this->blinConfigAppId();
        $SecretId = input("post.SecretId");
        $SecretKey = input("post.SecretKey");
        $bucket = input("post.bucket");
        $region = input("post.region");
        $domainName = input("post.domainName");
        if ($SecretId == '' || $SecretKey == '' || $bucket == '' || $region == '') {
            $this->error("请输入完整！");
        }
        $this->blinSaveOssConfig($appid, "QCloudOSS", [
            'SecretId' => $SecretId,
            'SecretKey' => $SecretKey,
            'bucket' => $bucket,
            'region' => $region,
            'domainName' => $domainName
        ]);
        $this->success("修改成功！");
    }''',
            "    //又拍云oss配置",
        ),
        "saveUpYunOSS": (
            '''    //又拍云oss配置
    public function saveUpYunOSS()
    {
        $appid = $this->blinConfigAppId();
        $ServiceName = input("post.ServiceName");
        $OperatorName = input("post.OperatorName");
        $OperatorPwd = input("post.OperatorPwd");
        $domainName = input("post.domainName");
        if ($ServiceName == '' || $OperatorName == '' || $OperatorPwd == '' || $domainName == '') {
            $this->error("请输入完整！");
        }
        $this->blinSaveOssConfig($appid, "UpYunOSS", [
            'ServiceName' => $ServiceName,
            'OperatorName' => $OperatorName,
            'OperatorPwd' => $OperatorPwd,
            'domainName' => $domainName
        ]);
        $this->success("修改成功！");
    }''',
            "    //七牛云oss配置",
        ),
        "saveQiniuOSS": (
            '''    //七牛云oss配置
    public function saveQiniuOSS()
    {
        $appid = $this->blinConfigAppId();
        $Access_Key = input("post.Access_Key");
        $Secret_Key = input("post.Secret_Key");
        $bucket = input("post.bucket");
        $domainName = input("post.domainName");
        if ($Access_Key == '' || $Secret_Key == '' || $bucket == '' || $domainName == '') {
            $this->error("请输入完整！");
        }
        $this->blinSaveOssConfig($appid, "QiniuOSS", [
            'Access_Key' => $Access_Key,
            'Secret_Key' => $Secret_Key,
            'bucket' => $bucket,
            'domainName' => $domainName
        ]);
        $this->success("修改成功！");
    }''',
            "    //附件管理",
        ),
    }
    for _, (block, next_marker) in oss_replacements.items():
        start_marker = block.split("\n", 1)[0] + "\n" + block.split("\n", 2)[1]
        source = replace_method(source, start_marker, next_marker, block, "oss_method")

    source = replace_method(source, "    public function sms_config()", "    public function payment()", "    " + SMS_METHODS, "sms_methods")

    source = source.replace('if ($info["oss_type"] == 1) $oss = new AlibabaCloudOSS();', 'if ($info["oss_type"] == 1) $oss = new AlibabaCloudOSS(isset($info["appid"]) ? $info["appid"] : 0);')
    source = source.replace('if ($info["oss_type"] == 2) $oss = new QCloudOSS();', 'if ($info["oss_type"] == 2) $oss = new QCloudOSS(isset($info["appid"]) ? $info["appid"] : 0);')
    source = source.replace('if ($info["oss_type"] == 3) $oss = new UpYunOSS();', 'if ($info["oss_type"] == 3) $oss = new UpYunOSS(isset($info["appid"]) ? $info["appid"] : 0);')
    source = source.replace('if ($info["oss_type"] == 4) $oss = new QiniuOSS();', 'if ($info["oss_type"] == 4) $oss = new QiniuOSS(isset($info["appid"]) ? $info["appid"] : 0);')

    save(ADMIN_SYSTEM, original, source, "app_scoped_config")


def patch_admin_index():
    source = ADMIN_INDEX.read_text(errors="ignore")
    original = source
    source = source.replace(
        '$upload = new Upload();',
        '$appid = intval(input("appid"));\n            if ($appid > 0 && method_exists($this, "blinRequireApp")) $this->blinRequireApp($appid);\n            $upload = new Upload(0, $appid);',
    )
    save(ADMIN_INDEX, original, source, "app_scoped_config")


def patch_app_controller():
    source = APP.read_text(errors="ignore")
    original = source
    if '"system_configuration" => "{}"' not in source:
        source = source.replace(
            '''                "security_configuration" => '{"security_switch":"1","encryption_type":"0","encryption_key":"","encryption_section":"0","data_signature":"0","time_difference_verification":"0"}',
            "im_configuration" =>''',
            '''                "security_configuration" => '{"security_switch":"1","encryption_type":"0","encryption_key":"","encryption_section":"0","data_signature":"0","time_difference_verification":"0"}',
                "system_configuration" => "{}",
                "email_configuration" => "{}",
                "sms_configuration" => "{}",
                "upload_configuration" => "{}",
                "oss_configuration" => "{}",
            "im_configuration" =>''',
            1,
        )
    save(APP, original, source, "app_scoped_config")


EMAIL_VIEW_SOURCE = r'''{extend name="layout" /}
{block name="body"}
<div class="container-fluid">
    <div class="row">
        <div class="col-lg-12">
            <div class="card mb-3">
                <div class="card-body">
                    <label class="form-label">选择应用</label>
                    <select class="form-select" id="config_appid">
                        {foreach $apps as $app}
                        <option value="{$app.appid}" {if $current_appid==$app.appid}selected{/if}>{$app.appname}（{$app.appid}）</option>
                        {/foreach}
                    </select>
                </div>
            </div>
            <div class="card">
                <header class="card-header"><div class="card-title">邮箱配置</div></header>
                <div class="card-body">
                    <form action="#!" method="post" name="edit-form" class="edit-form">
                        <input type="hidden" name="appid" value="{$current_appid}">
                        <div class="mb-3"><label class="form-label">邮箱账号</label><input class="form-control" type="text" id="username" name="username" value="{$info.username}" placeholder="请输入邮箱账号"></div>
                        <div class="mb-3"><label class="form-label">账号密码(授权码)</label><input class="form-control" type="text" id="password" name="password" value="{$info.password}" placeholder="请输入账号密码(授权码)"></div>
                        <div class="mb-3"><label class="form-label">发信方式</label><input class="form-control" type="text" id="host" name="host" value="{$info.host}" placeholder="smtp.qq.com"></div>
                        <div class="mb-3"><label class="form-label">发信端口</label><input class="form-control" type="text" id="port" name="port" value="{$info.port}" placeholder="465"></div>
                        <div class="mb-3"><label class="form-label">发件人名称</label><input class="form-control" type="text" id="fromName" name="fromName" value="{$info.fromName}" placeholder="请输入发件人名称"></div>
                        <div class="row">
                            <div class="col-md-6 mb-3"><label class="form-label">邮箱验证码有效期（秒）</label><input class="form-control" type="number" name="email_code_time" value="{$system_info.email_code_time}" placeholder="300"></div>
                            <div class="col-md-6 mb-3"><label class="form-label">邮箱验证码发送间隔（秒）</label><input class="form-control" type="number" name="email_code_interval_time" value="{$system_info.email_code_interval_time}" placeholder="60"></div>
                        </div>
                        <div class="mb-3"><label class="form-label">测试邮箱</label><input class="form-control" type="text" id="toEmail" name="toEmail" value="" placeholder="请输入测试邮箱"></div>
                        <button type="button" class="btn btn-primary me-1" id="submit_data">确 定</button>
                        <button type="button" class="btn btn-success me-1" id="send_email">测试发送</button>
                    </form>
                </div>
            </div>
        </div>
    </div>
    {if checkRight('system/editEmailTpl')}
    <div class="row">
        <div class="col-lg-12">
            <div class="card">
                <header class="card-header"><div class="card-title">邮件模板列表</div></header>
                <div class="card-body">
                    <table class="table">
                        <thead><tr><th>ID</th><th>名称</th><th>路径</th><th>操作</th></tr></thead>
                        <tbody>
                            {foreach $tplList as $key=>$vo}
                            <tr><td>{$key+1}</td><td>{$vo.name}</td><td>{$vo.path}</td><td><a href="#" onclick="editEmailTpl({$key})" class="btn btn-xs btn-info">编辑</a></td></tr>
                            {/foreach}
                        </tbody>
                    </table>
                </div>
            </div>
        </div>
    </div>
    {/if}
</div>
{/block}
{block name="js"}
<link rel="stylesheet" href="/static/layui/css/layui.css">
<script type="text/javascript" src="/static/layui/layui.js"></script>
<script>
    $("#config_appid").change(function () {
        window.location.href = "{:url('email')}?appid=" + $(this).val();
    });
    $("#submit_data").click(function () {
        var l = $('body').lyearloading({ opacity: 0.2, spinnerSize: 'lg' });
        if ($("#username").val() == '' || $("#password").val() == '' || $("#host").val() == '' || $("#port").val() == '') {
            l.destroy();
            notify.error('请填写完整邮箱配置');
            return false;
        }
        $.ajax({
            url: "{:url('email')}",
            type: "post",
            data: $(".edit-form").serialize(),
            dataType: "json",
            success: function (res) {
                l.destroy();
                if (res.code == 1) notify.success(res.msg, function () { window.location.reload(); }, 1000);
                else notify.error(res.msg);
            },
            error: function (res) { l.destroy(); notify.error(res.msg); }
        });
    });
    $("#send_email").click(function () {
        var l = $('body').lyearloading({ opacity: 0.2, spinnerSize: 'lg' });
        var toEmail = $("#toEmail").val();
        if (toEmail == '') { l.destroy(); notify.error('请输入测试邮箱'); return false; }
        $.ajax({
            url: "{:url('sendEmail')}",
            type: "post",
            data: { appid: "{$current_appid}", toEmail: toEmail },
            dataType: "json",
            success: function (res) { l.destroy(); if (res.code == 1) notify.success(res.msg); else notify.error(res.msg); },
            error: function (res) { l.destroy(); notify.error(res.msg); }
        });
    });
    function editEmailTpl(key) {
        layer.open({
            type: 2,
            title: "编辑邮件模板",
            area: ['85%', '80%'],
            content: "{:url('system/editEmailTpl')}?key=" + key,
            btn: ['选择', '取消'],
            yes: function (index, layero) {
                var iframeWin = window[layero.find('iframe')[0]['name']];
                var value = iframeWin.$('textarea[name="htmlcode"]').val();
                if ($.trim(value) === '') { layer.msg('请输入内容'); return false; }
                $.ajax({
                    url: "{:url('system/editEmailTpl')}",
                    type: "post",
                    data: { key: key, content: value },
                    dataType: "json",
                    success: function (res) { layer.msg(res.msg); if (res.code == 1) layer.close(index); },
                    error: function (res) { layer.msg(res.msg); }
                });
            }
        });
    }
</script>
{/block}
'''


SMS_VIEW_SOURCE = r'''{extend name="layout" /}
{block name="body"}
<div class="container-fluid">
    <div class="row">
        <div class="col-lg-12">
            <div class="card mb-3">
                <div class="card-body">
                    <label class="form-label">选择应用</label>
                    <select class="form-select" id="config_appid">
                        {foreach $apps as $app}
                        <option value="{$app.appid}" {if $current_appid==$app.appid}selected{/if}>{$app.appname}（{$app.appid}）</option>
                        {/foreach}
                    </select>
                </div>
            </div>
        </div>
        {if checkRight('system/saveAlibabaSample')}
        <div class="col-lg-6">
            <div class="card">
                <header class="card-header"><div class="card-title">阿里云短信配置</div></header>
                <div class="card-body">
                    <form action="#!" method="post" class="saveAlibabaSample">
                        <input type="hidden" name="appid" value="{$current_appid}">
                        <div class="mb-3"><label class="form-label">AccessKey ID</label><input class="form-control" type="text" id="accessKeyId" name="accessKeyId" value="{$other_info['AlibabaSample']['accessKeyId']}" placeholder="请输入AccessKey ID"></div>
                        <div class="mb-3"><label class="form-label">AccessKey Secret</label><input class="form-control" type="text" id="accessKeySecret" name="accessKeySecret" value="{$other_info['AlibabaSample']['accessKeySecret']}" placeholder="请输入AccessKey Secret"></div>
                        <div class="mb-3"><label class="form-label">短信签名名称</label><input class="form-control" type="text" id="signName" name="signName" value="{$other_info['AlibabaSample']['signName']}" placeholder="请输入短信签名名称"></div>
                        <div class="mb-3"><label class="form-label">短信模板CODE</label><input class="form-control" type="text" id="TemplateCode" name="TemplateCode" value="{$other_info['AlibabaSample']['TemplateCode']}" placeholder="请输入短信模板CODE"></div>
                        <div class="mb-3"><label class="form-label">短信模板变量值</label><input class="form-control" type="text" id="TemplateParam" name="TemplateParam" value="{$other_info['AlibabaSample']['TemplateParam']}" placeholder="code"></div>
                        <div class="row">
                            <div class="col-md-6 mb-3"><label class="form-label">短信验证码有效期（秒）</label><input class="form-control" type="number" name="phone_code_time" value="{$system_info.phone_code_time}" placeholder="300"></div>
                            <div class="col-md-6 mb-3"><label class="form-label">短信验证码发送间隔（秒）</label><input class="form-control" type="number" name="phone_code_interval_time" value="{$system_info.phone_code_interval_time}" placeholder="60"></div>
                        </div>
                        <div class="mb-3"><label class="form-label">测试手机号</label><input class="form-control" type="text" id="alibabaPhone" name="alibabaPhone" placeholder="请输入测试手机号"></div>
                        <button type="button" class="btn btn-primary me-1" id="saveAlibabaSample">确 定</button>
                        <button type="button" class="btn btn-info me-1" onclick="testAlibabaSample()">测 试</button>
                    </form>
                </div>
            </div>
        </div>
        {/if}
    </div>
</div>
{/block}
{block name="js"}
<script>
    $("#config_appid").change(function () {
        window.location.href = "{:url('sms_config')}?appid=" + $(this).val();
    });
    $("#saveAlibabaSample").click(function () {
        var l = $('body').lyearloading({ opacity: 0.2, spinnerSize: 'lg' });
        $.ajax({
            url: "{:url('saveAlibabaSample')}",
            type: "post",
            data: $(".saveAlibabaSample").serialize(),
            dataType: "json",
            success: function (res) {
                l.destroy();
                if (res.code == 1) notify.success(res.msg, function () { window.location.reload(); }, 1000);
                else notify.error(res.msg);
            },
            error: function (res) { l.destroy(); notify.error(res.msg); }
        });
    });
    function testAlibabaSample(){
        var l = $('body').lyearloading({ opacity: 0.2, spinnerSize: 'lg' });
        var phone = $("#alibabaPhone").val();
        if (phone == '') { l.destroy(); notify.error('请输入测试手机号'); return false; }
        $.ajax({
            url: "{:url('sendAlibabaSample')}",
            type: "post",
            data: { appid: "{$current_appid}", phone: phone },
            dataType: "json",
            success: function (res) { l.destroy(); if (res.code == 1) notify.success(res.msg); else notify.error(res.msg); },
            error: function (res) { l.destroy(); notify.error(res.msg); }
        });
    }
</script>
{/block}
'''


def patch_views():
    write_file(EMAIL_VIEW, EMAIL_VIEW_SOURCE, "app_scoped_email_view")
    write_file(SMS_VIEW, SMS_VIEW_SOURCE, "app_scoped_sms_view")

    source = UPLOAD_VIEW.read_text(errors="ignore")
    original = source
    if 'id="config_appid"' not in source:
        source = source.replace(
            '<div class="container-fluid">\n    <div class="row">',
            '''<div class="container-fluid">
    <div class="row">
        <div class="col-lg-12">
            <div class="card mb-3">
                <div class="card-body">
                    <label class="form-label">选择应用</label>
                    <select class="form-select" id="config_appid">
                        {foreach $apps as $app}
                        <option value="{$app.appid}" {if $current_appid==$app.appid}selected{/if}>{$app.appname}（{$app.appid}）</option>
                        {/foreach}
                    </select>
                </div>
            </div>
        </div>''',
            1,
        )
    if 'name="appid" value="{$current_appid}"' not in source:
        source = source.replace(
            '<form action="#!" method="post" name="edit-form" class="edit-form">',
            '<form action="#!" method="post" name="edit-form" class="edit-form">\n                        <input type="hidden" name="appid" value="{$current_appid}">',
        )
        for form_class in ["saveAlibabaCloudOSS", "saveQCloudOSS", "saveUpYunOSS", "saveQiniuOSS"]:
            source = source.replace(
                f'<form action="#!" method="post" class="{form_class}">',
                f'<form action="#!" method="post" class="{form_class}">\n                        <input type="hidden" name="appid" value="{{$current_appid}}">',
            )
    if 'window.location.href = "{:url(\'upload\')}?appid="' not in source:
        source = source.replace(
            '<script>\n    $("#submit_data").click(function () {',
            '''<script>
    $("#config_appid").change(function () {
        window.location.href = "{:url('upload')}?appid=" + $(this).val();
    });
    $("#submit_data").click(function () {''',
            1,
        )
    save(UPLOAD_VIEW, original, source, "app_scoped_upload_view")


def main():
    patch_database()
    patch_tool_classes()
    patch_base_controller()
    patch_api_controller()
    patch_system_controller()
    patch_admin_index()
    patch_app_controller()
    patch_views()


if __name__ == "__main__":
    main()
