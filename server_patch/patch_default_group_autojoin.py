from pathlib import Path


ROOT = Path("/www/wwwroot/blinlin")
API = ROOT / "application/api/controller/Api.php"


def backup(path: Path) -> None:
    bak = path.with_name(path.name + ".bak_default_group_autojoin_20260621")
    if not bak.exists():
        bak.write_text(path.read_text(encoding="utf-8"), encoding="utf-8")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    if old not in text:
        raise RuntimeError(f"missing marker: {label}")
    return text.replace(old, new, 1)


def main() -> None:
    backup(API)
    text = API.read_text(encoding="utf-8")

    text = replace_once(
        text,
        '''    private function blinFeatureOpen($key)
    {
        return intval($this->blinImConfig($key, 0)) === 0;
    }
''',
        '''    private function blinFeatureOpen($key)
    {
        return intval($this->blinImConfig($key, 0)) === 0;
    }

    private function blinDefaultGroupJoinOpen()
    {
        return intval($this->blinImConfig("default_group_join_switch", 1)) === 0;
    }

    private function blinDefaultGroupNeeded()
    {
        return $this->blinFeatureOpen("default_group_switch")
            || $this->blinDefaultGroupJoinOpen()
            || intval($this->blinImConfig("default_group_id", 0)) > 0;
    }
''',
        "default_group_helpers",
    )

    text = replace_once(
        text,
        '''    private function blinDefaultGroup()
    {
        if (!$this->blinFeatureOpen("default_group_switch")) return null;
        $this->ensure_im_group_tables();
''',
        '''    private function blinDefaultGroup()
    {
        if (!$this->blinDefaultGroupNeeded()) return null;
        $this->ensure_im_group_tables();
''',
        "default_group_guard",
    )

    text = replace_once(
        text,
        '''        if (!$group) {
            $group = Db::name("im_groups")->where("appid", $this->appid)->where("default_group", 1)->where("status", 1)->order("id", "asc")->find();
        }
''',
        '''        if (!$group) {
            $group = Db::name("im_groups")->where("appid", $this->appid)->where("default_group", 1)->order("status desc,id asc")->find();
        }
''',
        "default_group_find_existing",
    )

    text = replace_once(
        text,
        '''        return $payload;
    }

    private function blinDefaultGroup()
''',
        '''        return $payload;
    }

    private function blinSyncWukongGroupChannel($group, $userIds = [])
    {
        if (!config("wukongim.enable") || !$group || !isset($group["group_no"]) || trim(strval($group["group_no"])) === "") return;
        try {
            $subscribers = [];
            foreach ((array)$userIds as $uid) {
                $uid = intval($uid);
                if ($uid > 0) $subscribers[] = $this->appid . "_" . $uid;
            }
            $subscribers = array_values(array_unique($subscribers));
            $wkim = new \\app\\common\\tool\\WukongIM();
            try { $wkim->createChannel(strval($group["group_no"]), 2, $subscribers); } catch (\\Exception $e) {}
            if ($subscribers) {
                try { $wkim->addChannelSubscribers(strval($group["group_no"]), 2, $subscribers); } catch (\\Exception $e) {}
            }
        } catch (\\Exception $e) {
        }
    }

    private function blinDefaultGroup()
''',
        "wukong_group_sync_helper",
    )

    text = replace_once(
        text,
        '''        if ($ownerId > 0) $this->blinAddUserToGroup($group, $ownerId, 2);
        return $group;
''',
        '''        $this->blinSyncWukongGroupChannel($group);
        if ($ownerId > 0) $this->blinAddUserToGroup($group, $ownerId, 2);
        return $group;
''',
        "default_group_sync_channel",
    )

    text = replace_once(
        text,
        '''        $count = Db::name("im_group_members")->where("group_id", intval($group["id"]))->where("status", 1)->count();
        Db::name("im_groups")->where("id", intval($group["id"]))->update(["member_count"=>$count, "update_time"=>$now]);
        return true;
''',
        '''        $count = Db::name("im_group_members")->where("group_id", intval($group["id"]))->where("status", 1)->count();
        Db::name("im_groups")->where("id", intval($group["id"]))->update(["member_count"=>$count, "update_time"=>$now]);
        $this->blinSyncWukongGroupChannel($group, [intval($userId)]);
        return true;
''',
        "add_user_group_sync_channel",
    )

    text = replace_once(
        text,
        '''    private function blinAutoJoinDefaultGroup($userId)
    {
        try {
            if (!$this->blinFeatureOpen("default_group_switch")) return;
            if (!$this->blinFeatureOpen("default_group_join_switch")) return;
            $group = $this->blinDefaultGroup();
            if ($group) $this->blinAddUserToGroup($group, intval($userId), 0);
        } catch (\\Exception $e) {
        }
    }
''',
        '''    private function blinAutoJoinDefaultGroup($userId)
    {
        try {
            if (!$this->blinDefaultGroupJoinOpen()) return;
            $group = $this->blinDefaultGroup();
            if ($group) $this->blinAddUserToGroup($group, intval($userId), 0);
        } catch (\\Exception $e) {
        }
    }
''',
        "auto_join_default_group",
    )

    text = replace_once(
        text,
        '''        if ($this->blinFeatureOpen("default_group_switch")) {
            $group = $this->blinDefaultGroup();
            if ($group && $this->blinFeatureOpen("default_group_join_switch")) $this->blinAddUserToGroup($group, intval($user["id"]), 0);
        }
''',
        '''        if ($this->blinDefaultGroupNeeded()) {
            $group = $this->blinDefaultGroup();
            if ($group && $this->blinDefaultGroupJoinOpen()) $this->blinAddUserToGroup($group, intval($user["id"]), 0);
        }
''',
        "group_list_default_group",
    )

    API.write_text(text, encoding="utf-8")
    print("patched default group auto join")


if __name__ == "__main__":
    main()
