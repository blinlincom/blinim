from pathlib import Path


ROOT = Path("/www/wwwroot/blinlin")
TRAIT = ROOT / "application/api/controller/traits/ImApiTrait.php"


def backup(path: Path) -> None:
    bak = path.with_name(path.name + ".bak_default_group_avatar_keep_20260621")
    if not bak.exists():
        bak.write_text(path.read_text(encoding="utf-8"), encoding="utf-8")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    if old not in text:
        raise RuntimeError(f"missing marker: {label}")
    return text.replace(old, new, 1)


def main() -> None:
    backup(TRAIT)
    text = TRAIT.read_text(encoding="utf-8")

    text = replace_once(
        text,
        '''    private function blinTraitFeatureOpen($key)
    {
        return intval($this->blinTraitImConfig($key, 1)) === 0;
    }

    private function blinTraitSyncChannel($group, $uids = [], $create = false)
''',
        '''    private function blinTraitFeatureOpen($key)
    {
        return intval($this->blinTraitImConfig($key, 1)) === 0;
    }

    private function blinTraitDefaultGroupJoinOpen()
    {
        return intval($this->blinTraitImConfig('default_group_join_switch', 1)) === 0;
    }

    private function blinTraitDefaultGroupNeeded()
    {
        return $this->blinTraitFeatureOpen('default_group_switch')
            || $this->blinTraitDefaultGroupJoinOpen()
            || intval($this->blinTraitImConfig('default_group_id', 0)) > 0;
    }

    private function blinTraitGeneratedGroupAvatar($avatar)
    {
        $avatar = strtolower(trim(strval($avatar)));
        return $avatar !== '' && strpos($avatar, '/uploads/im_group_avatar/') !== false;
    }

    private function blinTraitSyncChannel($group, $uids = [], $create = false)
''',
        "trait_default_group_helpers",
    )

    text = replace_once(
        text,
        '''    private function blinTraitDefaultGroup()
    {
        if (!$this->blinTraitFeatureOpen('default_group_switch')) return null;
        $this->ensure_im_group_tables();
''',
        '''    private function blinTraitDefaultGroup()
    {
        if (!$this->blinTraitDefaultGroupNeeded()) return null;
        $this->ensure_im_group_tables();
''',
        "trait_default_group_guard",
    )

    text = replace_once(
        text,
        '''            $group = Db::name('im_groups')->where('appid', $this->appid)->where('id', $groupId)->where('status', 1)->find();
''',
        '''            $group = Db::name('im_groups')->where('appid', $this->appid)->where('id', $groupId)->find();
''',
        "trait_find_default_by_id_even_disabled",
    )

    text = replace_once(
        text,
        '''            $group = Db::name('im_groups')->where('appid', $this->appid)->where('default_group', 1)->where('status', 1)->order('id asc')->find();
''',
        '''            $group = Db::name('im_groups')->where('appid', $this->appid)->where('default_group', 1)->order('status desc,id asc')->find();
''',
        "trait_find_existing_default_even_disabled",
    )

    text = replace_once(
        text,
        '''        $update = [
            'name' => $name,
            'avatar' => $avatar,
            'notice' => $notice,
            'owner_id' => $ownerId,
            'default_group' => 1,
            'status' => 1,
            'update_time' => $now,
        ];
        if ($group) {
            Db::name('im_groups')->where('appid', $this->appid)->where('id', intval($group['id']))->update($update);
''',
        '''        $update = [
            'name' => $name,
            'notice' => $notice,
            'owner_id' => $ownerId,
            'default_group' => 1,
            'status' => 1,
            'update_time' => $now,
        ];
        if (!$group) {
            $update['avatar'] = $avatar;
        } else {
            $currentAvatar = trim(strval(isset($group['avatar']) ? $group['avatar'] : ''));
            if ($avatar !== '' && ($currentAvatar === '' || !$this->blinTraitGeneratedGroupAvatar($currentAvatar))) {
                $update['avatar'] = $avatar;
            }
        }
        if ($group) {
            Db::name('im_groups')->where('appid', $this->appid)->where('id', intval($group['id']))->update($update);
''',
        "trait_default_group_keep_generated_avatar",
    )

    text = replace_once(
        text,
        '''    private function blinTraitAutoJoinDefaultGroup($userId)
    {
        if (!$this->blinTraitFeatureOpen('default_group_switch') || !$this->blinTraitFeatureOpen('default_group_join_switch')) return;
        try {
            $group = $this->blinTraitDefaultGroup();
''',
        '''    private function blinTraitAutoJoinDefaultGroup($userId)
    {
        if (!$this->blinTraitDefaultGroupJoinOpen()) return;
        try {
            $group = $this->blinTraitDefaultGroup();
''',
        "trait_auto_join_switch",
    )

    TRAIT.write_text(text, encoding="utf-8")
    print("patched trait default group avatar keep")


if __name__ == "__main__":
    main()
