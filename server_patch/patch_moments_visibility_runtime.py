from datetime import datetime
from pathlib import Path


API = Path("/www/wwwroot/blinlin/application/api/controller/Api.php")


def replace_between(source: str, start_marker: str, end_marker: str, replacement: str) -> str:
    start = source.index(start_marker)
    end = source.index(end_marker, start)
    return source[:start] + replacement + source[end:]


def main() -> None:
    source = API.read_text()
    backup = API.with_suffix(API.suffix + f".bak_moments_visibility_runtime_{datetime.now():%Y%m%d%H%M%S}")
    backup.write_text(source)

    source = source.replace(
        'if ($type === "public") return "公开";',
        'if ($type === "public") return "全员可看";',
    )

    source = source.replace(
        'if ($globalVisibility !== "all" && $visibilityType === "public") $visibilityType = "friends";',
        'if ($globalVisibility !== "all") {\n'
        '            $visibilityType = "friends";\n'
        '            $visibleUserIds = [];\n'
        '            $hiddenUserIds = [];\n'
        '        }',
    )

    source = replace_between(
        source,
        "    private function blinMomentCanView",
        "    private function blinMomentImages",
        '''    private function blinMomentCanView($moment, $userId)
    {
        if (!$moment || intval($moment["appid"]) !== intval($this->appid)) return false;
        $ownerId = intval(isset($moment["user_id"]) ? $moment["user_id"] : 0);
        $viewerId = intval($userId);
        if ($ownerId <= 0 || $viewerId <= 0) return false;
        if ($ownerId === $viewerId) return true;
        $type = $this->blinMomentVisibilityType(isset($moment["visibility_type"]) ? $moment["visibility_type"] : (isset($moment["visibility"]) ? $moment["visibility"] : "friends"));
        if ($type === "private") return false;
        if (!$this->blinMomentScopeAllows($moment, $viewerId)) return false;
        if ($type === "public") return $this->blinMomentsVisibility() === "all";
        if ($type === "include" && $this->blinMomentsVisibility() === "all") return true;
        if ($type === "exclude" && $this->blinMomentsVisibility() === "all") return true;
        try {
            return !!Db::table("im_friends")
                ->where("appid", "in", [intval($this->appid), 0])
                ->where("user_id", $viewerId)
                ->where("friend_id", $ownerId)
                ->where("status", 1)
                ->find();
        } catch (\\Exception $e) {
            return false;
        }
    }

''',
    )

    source = replace_between(
        source,
        '        $globalVisibility = $this->blinMomentsVisibility();',
        '        $visibility = $visibilityType === "public" ? "all" : "friends";',
        '''        $globalVisibility = $this->blinMomentsVisibility();
        $visibilityType = $this->blinMomentVisibilityType(input("visibility_type") ?: input("moment_visibility") ?: $globalVisibility);
        $visibleUserIds = $this->blinMomentIdList(input("visible_user_ids") ?: input("allow_user_ids") ?: "");
        $hiddenUserIds = $this->blinMomentIdList(input("hidden_user_ids") ?: input("deny_user_ids") ?: "");
        if ($globalVisibility !== "all") {
            $visibilityType = "friends";
            $visibleUserIds = [];
            $hiddenUserIds = [];
        } else {
            $friendIds = $this->blinMomentFriendIds(intval($user["id"]));
            $friendMap = array_flip(array_map("intval", $friendIds));
            $visibleUserIds = array_values(array_filter($visibleUserIds, function ($id) use ($friendMap) {
                return isset($friendMap[intval($id)]);
            }));
            $hiddenUserIds = array_values(array_filter($hiddenUserIds, function ($id) use ($friendMap) {
                return isset($friendMap[intval($id)]);
            }));
        }
        if ($visibilityType === "include" && !$visibleUserIds) $this->json(0, "请选择可见好友");
        if ($visibilityType === "exclude" && !$hiddenUserIds) $this->json(0, "请选择不可见好友");
''',
    )

    API.write_text(source)
    print(f"patched {API}")
    print(f"backup {backup}")


if __name__ == "__main__":
    main()
