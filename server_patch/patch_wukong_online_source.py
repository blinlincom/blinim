#!/usr/bin/env python3
"""Use WuKongIM long connection as the only IM online source."""
from pathlib import Path
import shutil
import time


ROOT = Path("/www/wwwroot/blinlin")
TRAIT = ROOT / "app/api/controller/traits/ImApiTrait.php"


def backup(path: Path) -> None:
    shutil.copy2(
        path,
        path.with_suffix(
            path.suffix + f".bak_wukong_online_source_{time.strftime('%Y%m%d%H%M%S')}"
        ),
    )


def replace_function(source: str, name: str, replacement: str) -> str:
    marker = f"    public function {name}("
    start = source.find(marker)
    if start < 0:
        raise SystemExit(f"{name} not found")
    brace = source.find("{", start)
    if brace < 0:
        raise SystemExit(f"{name} body not found")
    depth = 0
    for i in range(brace, len(source)):
        ch = source[i]
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return source[:start] + replacement + source[i + 1 :]
    raise SystemExit(f"{name} end not found")


backup(TRAIT)
source = TRAIT.read_text(errors="ignore")

connect_info = r'''    public function get_im_connect_info()
    {
        $data = input();
        $rule = ['usertoken|用户token' => 'require'];
        $validate = (new Validate())->rule($rule);
        if (!$validate->check($data)) { $this->json(0, $validate->getError()); }
        $user_all_info = $this->blinTraitAuthenticatedUser();
        $uid = $this->appid . "_" . $user_all_info["id"];
        $device_flag = input("device_flag") === "" ? 0 : intval(input("device_flag"));
        $token = md5($uid . "_" . md5(strval(input("usertoken"))) . "_" . $device_flag);
        $platform = trim(strval(input("platform") ?: ""));
        $terminal = trim(strval(input("terminal") ?: input("device_type") ?: ""));
        $device = trim(strval(input("device") ?: $terminal ?: $platform ?: $device_flag));
        try {
            $wkim = new \app\common\tool\WukongIM();
            $wkim->updateUserToken($uid, $token, $device_flag, 1);
            $route = $wkim->getUserRoute($uid, intval(config('wukongim.route_intranet')));
            $this->json(1, "success", ["uid"=>$uid,"token"=>$token,"device_flag"=>$device_flag,"device_level"=>1,"device"=>$device,"platform"=>$platform,"terminal"=>$terminal,"online_source"=>"wukongim","route"=>$route,"ws_addr"=>isset($route["ws_addr"])?$route["ws_addr"]:config('wukongim.ws_url'),"tcp_addr"=>isset($route["tcp_addr"])?$route["tcp_addr"]:"","wss_addr"=>isset($route["wss_addr"])?$route["wss_addr"]:""]);
        } catch (\Exception $e) { $this->json(0, "悟空IM连接信息获取失败：" . $e->getMessage()); }
    }
'''

get_online = r'''    public function get_im_online_status()
    {
        $data = input();
        $rule = ['usertoken|用户token' => 'require', 'user_id|用户ID' => 'require|number'];
        $validate = (new Validate())->rule($rule);
        if (!$validate->check($data)) {
            $this->json(0, $validate->getError());
        }
        $this->blinTraitAuthenticatedUser();
        $peer = Db::name("user")->where("id", intval($data["user_id"]))->where("appid", $this->appid)->find();
        if (!$peer) {
            $this->json(0, "用户不存在");
        }
        $uid = $this->appid . "_" . intval($peer["id"]);
        $online = false;
        $online_uids = [];
        $api_error = "";
        try {
            if (config('wukongim.enable')) {
                $online_uids = (new \app\common\tool\WukongIM())->getOnlineStatus([$uid]);
                if (!is_array($online_uids)) $online_uids = [];
                foreach ($online_uids as $ou) {
                    if (is_string($ou) && $ou === $uid) {
                        $online = true;
                        break;
                    }
                    if (is_array($ou)) {
                        $ou_uid = isset($ou['uid']) ? strval($ou['uid']) : (isset($ou['user_id']) ? strval($ou['user_id']) : '');
                        $ou_online = isset($ou['online']) ? intval($ou['online']) : (isset($ou['is_online']) ? intval($ou['is_online']) : 0);
                        if ($ou_uid === $uid && $ou_online === 1) {
                            $online = true;
                            break;
                        }
                    }
                }
            } else {
                $api_error = "悟空IM未启用";
            }
        } catch (\Exception $e) {
            $api_error = $e->getMessage();
        }
        $last_seen = "";
        if (!$online) {
            try {
                $seenRow = Db::name("im_online_status")
                    ->where("appid", intval($this->appid))
                    ->where("uid", $uid)
                    ->order("update_time desc")
                    ->find();
                if ($seenRow) {
                    if (isset($seenRow["last_seen"]) && trim(strval($seenRow["last_seen"])) !== "" && strval($seenRow["last_seen"]) !== "0000-00-00 00:00:00") {
                        $last_seen = strval($seenRow["last_seen"]);
                    } elseif (isset($seenRow["update_time"])) {
                        $last_seen = strval($seenRow["update_time"]);
                    }
                }
            } catch (\Exception $e) {}
        }
        $this->json(1, "success", [
            "uid"=>$uid,
            "user_id"=>intval($peer["id"]),
            "online"=>$online,
            "device"=>"",
            "platform"=>"",
            "terminal"=>"",
            "device_flag"=>0,
            "last_update_time"=>"",
            "last_seen"=>$last_seen,
            "online_uids"=>$online_uids,
            "source"=>"wukongim",
            "api_error"=>$api_error,
        ]);
    }
'''

offline = r'''    public function im_online_heartbeat()
    {
        $data = input();
        $rule = ['usertoken|用户token' => 'require'];
        $validate = (new Validate())->rule($rule);
        if (!$validate->check($data)) { $this->json(0, $validate->getError()); }
        $user_all_info = $this->blinTraitAuthenticatedUser();
        $uid = $this->appid . "_" . intval($user_all_info["id"]);
        $device_flag = input("device_flag") === "" ? 0 : intval(input("device_flag"));
        $platform = trim(strval(input("platform") ?: ""));
        $terminal = trim(strval(input("terminal") ?: input("device_type") ?: ""));
        $device = trim(strval(input("device") ?: $terminal ?: $platform ?: $device_flag));
        $onlineRaw = strtolower(strval(input("online") === "" ? "0" : input("online")));
        $online = !($onlineRaw === "0" || $onlineRaw === "false" || $onlineRaw === "offline");
        if ($online) {
            $this->json(0, "在线状态由悟空IM长连接维护");
        }
        try {
            if (config('wukongim.enable')) {
                (new \app\common\tool\WukongIM())->forceDeviceQuit($uid, $device_flag > 0 ? $device_flag : null);
            }
        } catch (\Exception $e) {
            $this->json(0, "悟空IM离线失败：" . $e->getMessage());
        }
        $now = date('Y-m-d H:i:s');
        try {
            Db::execute("CREATE TABLE IF NOT EXISTS `mr_im_online_status` (`id` int(11) NOT NULL AUTO_INCREMENT, `appid` int(11) NOT NULL DEFAULT 0, `uid` varchar(64) NOT NULL DEFAULT '', `user_id` int(11) NOT NULL DEFAULT 0, `online` tinyint(1) NOT NULL DEFAULT 0, `last_event` varchar(64) NOT NULL DEFAULT '', `last_seen` datetime DEFAULT NULL, `raw_data` text, `update_time` datetime DEFAULT NULL, `device` varchar(32) NOT NULL DEFAULT '', `platform` varchar(32) NOT NULL DEFAULT '', `terminal` varchar(32) NOT NULL DEFAULT '', `device_flag` int(11) NOT NULL DEFAULT 0, PRIMARY KEY (`id`), UNIQUE KEY `uk_uid` (`uid`), KEY `idx_user_id` (`user_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8;");
            foreach (["last_event varchar(64) NOT NULL DEFAULT ''", "last_seen datetime DEFAULT NULL", "raw_data text", "update_time datetime DEFAULT NULL", "device varchar(32) NOT NULL DEFAULT ''", "platform varchar(32) NOT NULL DEFAULT ''", "terminal varchar(32) NOT NULL DEFAULT ''", "device_flag int(11) NOT NULL DEFAULT 0"] as $col) {
                $name = explode(' ', $col)[0];
                try { Db::execute("ALTER TABLE `mr_im_online_status` ADD COLUMN `".$name."` ".$col); } catch (\Exception $e) {}
            }
            $raw = json_encode(["event"=>"offline", "source"=>"client_logout", "device"=>$device, "platform"=>$platform, "terminal"=>$terminal, "device_flag"=>$device_flag], JSON_UNESCAPED_UNICODE);
            $sql = "INSERT INTO `mr_im_online_status` (`appid`,`uid`,`user_id`,`online`,`last_event`,`last_seen`,`raw_data`,`update_time`,`device`,`platform`,`terminal`,`device_flag`) VALUES (:appid,:uid,:user_id,0,'offline',:last_seen,:raw_data,:update_time,:device,:platform,:terminal,:device_flag) ON DUPLICATE KEY UPDATE `online`=0,`last_event`='offline',`last_seen`=VALUES(`last_seen`),`raw_data`=VALUES(`raw_data`),`update_time`=VALUES(`update_time`),`device`=VALUES(`device`),`platform`=VALUES(`platform`),`terminal`=VALUES(`terminal`),`device_flag`=VALUES(`device_flag`)";
            Db::execute($sql, ['appid'=>$this->appid, 'uid'=>$uid, 'user_id'=>intval($user_all_info["id"]), 'last_seen'=>$now, 'raw_data'=>$raw, 'update_time'=>$now, 'device'=>$device, 'platform'=>$platform, 'terminal'=>$terminal, 'device_flag'=>$device_flag]);
        } catch (\Exception $e) {
            $this->json(0, "离线状态记录失败：" . $e->getMessage());
        }
        $this->json(1, "success", ["uid"=>$uid, "online"=>false, "device"=>$device, "platform"=>$platform, "terminal"=>$terminal, "device_flag"=>$device_flag, "update_time"=>$now]);
    }
'''

source = replace_function(source, "get_im_connect_info", connect_info)
source = replace_function(source, "get_im_online_status", get_online)
source = replace_function(source, "im_online_heartbeat", offline)
source = source.replace(
    "    // IM在线心跳：客户端前台定时上报，退出后超时自动判离线\n    public function im_online_heartbeat()",
    "    // IM显式离线：在线状态由悟空IM长连接维护\n    public function im_online_heartbeat()",
)
TRAIT.write_text(source)
print("patched WuKongIM online source")
