#!/usr/bin/env python3
"""Make backend user deletion clean all user-related IM and business records."""

from datetime import datetime
from pathlib import Path
import os
import re
import shutil


ROOT = Path(os.environ.get("BLIN_ROOT", "/www/wwwroot/blinlin"))
USER_CONTROLLER = ROOT / "application/admin/controller/User.php"

HELPER_BLOCK = r'''
    // blin-user-delete-cleanup-start
    private function blinUserDeleteMoneyField($moneyType)
    {
        return intval($moneyType) == 1 ? "integral" : "money";
    }

    private function blinUserDeleteRefundPendingMoney($appid, $userId)
    {
        $appid = intval($appid);
        $userId = intval($userId);
        $summary = [
            "transfer_count" => 0,
            "transfer_amount" => 0,
            "red_packet_count" => 0,
            "red_packet_amount" => 0,
        ];

        $transferRows = Db::name("im_transfer_order")
            ->where("appid", $appid)
            ->where("status", 0)
            ->where(function($query) use ($userId) {
                $query->where("sender_id", $userId)->whereOr("receiver_id", $userId);
            })
            ->lock(true)
            ->select();
        foreach (($transferRows ?: []) as $row) {
            $refund = floatval(isset($row["hold_amount"]) ? $row["hold_amount"] : 0);
            if ($refund <= 0) {
                $refund = floatval(isset($row["amount"]) ? $row["amount"] : 0);
                if (intval(isset($row["fee_payer"]) ? $row["fee_payer"] : 0) == 1) {
                    $refund += floatval(isset($row["fee"]) ? $row["fee"] : 0);
                }
            }
            $senderId = intval(isset($row["sender_id"]) ? $row["sender_id"] : 0);
            if ($refund <= 0 || $senderId <= 0 || $senderId == $userId) continue;
            $field = $this->blinUserDeleteMoneyField(isset($row["money_type"]) ? $row["money_type"] : 0);
            $sender = Db::name("user")->where("appid", $appid)->where("id", $senderId)->lock(true)->find();
            if (!$sender) continue;
            Db::name("user")->where("appid", $appid)->where("id", $senderId)->update([$field => floatval($sender[$field]) + $refund]);
            add_user_bill(["id"=>$senderId, "appid"=>$appid], 9, "+" . number_format($refund, 2, ".", ""), "收款方账号已删除，待收款转账已退回", intval(isset($row["money_type"]) ? $row["money_type"] : 0), 0, isset($row["trade_no"]) ? strval($row["trade_no"]) : "");
            $summary["transfer_count"]++;
            $summary["transfer_amount"] += $refund;
        }

        $packetRows = Db::name("im_red_packet_order")
            ->where("appid", $appid)
            ->where("status", 0)
            ->where("remaining_amount", ">", 0)
            ->where(function($query) use ($userId) {
                $query->where("sender_id", $userId)->whereOr("receiver_id", $userId);
            })
            ->lock(true)
            ->select();
        foreach (($packetRows ?: []) as $row) {
            $refund = floatval(isset($row["remaining_amount"]) ? $row["remaining_amount"] : 0);
            $senderId = intval(isset($row["sender_id"]) ? $row["sender_id"] : 0);
            if ($refund <= 0 || $senderId <= 0 || $senderId == $userId) continue;
            $field = $this->blinUserDeleteMoneyField(isset($row["money_type"]) ? $row["money_type"] : 0);
            $sender = Db::name("user")->where("appid", $appid)->where("id", $senderId)->lock(true)->find();
            if (!$sender) continue;
            Db::name("user")->where("appid", $appid)->where("id", $senderId)->update([$field => floatval($sender[$field]) + $refund]);
            add_user_bill(["id"=>$senderId, "appid"=>$appid], 15, "+" . number_format($refund, 2, ".", ""), "接收方账号已删除，未领取红包已退回", intval(isset($row["money_type"]) ? $row["money_type"] : 0), 0, isset($row["trade_no"]) ? strval($row["trade_no"]) : "");
            $summary["red_packet_count"]++;
            $summary["red_packet_amount"] += $refund;
        }
        return $summary;
    }

    private function blinUserDeleteRefreshGroupCounts($appid, $groupIds)
    {
        $appid = intval($appid);
        $groupIds = array_values(array_unique(array_filter(array_map("intval", (array)$groupIds))));
        foreach ($groupIds as $groupId) {
            if ($groupId <= 0) continue;
            $count = Db::name("im_group_members")->where("appid", $appid)->where("group_id", $groupId)->where("status", 1)->count();
            Db::name("im_groups")->where("appid", $appid)->where("id", $groupId)->update([
                "member_count" => intval($count),
                "update_time" => date("Y-m-d H:i:s"),
            ]);
        }
    }

    private function blinUserDeleteCleanup($user)
    {
        if (!$user) return;
        $userId = intval($user["id"]);
        $appid = intval($user["appid"]);
        if ($userId <= 0 || $appid <= 0) return;
        $uid = $appid . "_" . $userId;

        $groupIds = Db::name("im_group_members")->where("appid", $appid)->where("user_id", $userId)->column("group_id");
        $ownedGroupIds = Db::name("im_groups")->where("appid", $appid)->where("owner_id", $userId)->column("id");
        $allGroupIds = array_values(array_unique(array_merge((array)$groupIds, (array)$ownedGroupIds)));

        $this->blinUserDeleteRefundPendingMoney($appid, $userId);

        Db::name("messages")->where("appid", $appid)->where(function($query) use ($userId) {
            $query->where("receiver_id", $userId)->whereOr("sender_id", $userId);
        })->delete();
        Db::name("im_group_messages")->where("appid", $appid)->where("sender_id", $userId)->delete();
        Db::name("im_message_log")->where("appid", $appid)->where(function($query) use ($userId, $uid) {
            $query->where("from_user_id", $userId)->whereOr("channel_user_id", $userId)->whereOr("from_uid", $uid)->whereOr("channel_id", $uid);
        })->delete();
        Db::name("im_offline_message")->where("appid", $appid)->where(function($query) use ($uid) {
            $query->where("from_uid", $uid)->whereOr("channel_id", $uid)->whereOr("to_uids", "like", "%" . $uid . "%");
        })->delete();

        Db::table("im_friends")->where("appid", $appid)->where(function($query) use ($userId) {
            $query->where("user_id", $userId)->whereOr("friend_id", $userId);
        })->delete();
        Db::table("im_friend_requests")->where("appid", $appid)->where(function($query) use ($userId) {
            $query->where("from_user_id", $userId)->whereOr("to_user_id", $userId);
        })->delete();
        Db::table("im_chat_clear_state")->where("appid", $appid)->where(function($query) use ($userId) {
            $query->where("user_id", $userId)->whereOr("peer_id", $userId);
        })->delete();

        Db::name("im_group_members")->where("appid", $appid)->where("user_id", $userId)->delete();
        Db::name("im_group_clear_state")->where("appid", $appid)->where("user_id", $userId)->delete();
        Db::name("im_group_read_state")->where("appid", $appid)->where("user_id", $userId)->delete();
        Db::name("im_groups")->where("appid", $appid)->where("owner_id", $userId)->update([
            "owner_id" => 0,
            "status" => 0,
            "update_time" => date("Y-m-d H:i:s"),
        ]);
        $this->blinUserDeleteRefreshGroupCounts($appid, $allGroupIds);

        Db::name("im_call_sessions")->where("appid", $appid)->where(function($query) use ($userId, $uid) {
            $query->where("caller_user_id", $userId)->whereOr("callee_user_id", $userId)->whereOr("caller_uid", $uid)->whereOr("callee_uid", $uid);
        })->delete();
        Db::name("im_call_signals")->where("appid", $appid)->where(function($query) use ($userId, $uid) {
            $query->where("from_user_id", $userId)->whereOr("to_user_id", $userId)->whereOr("from_uid", $uid)->whereOr("to_uid", $uid);
        })->delete();

        Db::name("im_transfer_order")->where("appid", $appid)->where(function($query) use ($userId) {
            $query->where("sender_id", $userId)->whereOr("receiver_id", $userId);
        })->delete();
        $packetIds = Db::name("im_red_packet_order")->where("appid", $appid)->where(function($query) use ($userId) {
            $query->where("sender_id", $userId)->whereOr("receiver_id", $userId);
        })->column("id");
        if ($packetIds) {
            Db::name("im_red_packet_claim")->where("appid", $appid)->whereIn("red_packet_id", $packetIds)->delete();
        }
        Db::name("im_red_packet_claim")->where("appid", $appid)->where("user_id", $userId)->delete();
        Db::name("im_red_packet_order")->where("appid", $appid)->where(function($query) use ($userId) {
            $query->where("sender_id", $userId)->whereOr("receiver_id", $userId);
        })->delete();

        $momentIds = Db::name("im_moments")->where("appid", $appid)->where("user_id", $userId)->column("id");
        if ($momentIds) {
            Db::name("im_moment_comments")->where("appid", $appid)->whereIn("moment_id", $momentIds)->delete();
            Db::name("im_moment_likes")->where("appid", $appid)->whereIn("moment_id", $momentIds)->delete();
            Db::name("im_moment_notifications")->where("appid", $appid)->whereIn("moment_id", $momentIds)->delete();
        }
        Db::name("im_moment_comments")->where("appid", $appid)->where(function($query) use ($userId) {
            $query->where("user_id", $userId)->whereOr("reply_user_id", $userId);
        })->delete();
        Db::name("im_moment_likes")->where("appid", $appid)->where("user_id", $userId)->delete();
        Db::name("im_moment_notifications")->where("appid", $appid)->where(function($query) use ($userId) {
            $query->where("actor_id", $userId)->whereOr("receiver_id", $userId);
        })->delete();
        Db::name("im_moments")->where("appid", $appid)->where(function($query) use ($userId) {
            $query->where("user_id", $userId)->whereOr("deleted_by", $userId);
        })->delete();

        Db::name("message_notification")->where("appid", $appid)->where(function($query) use ($userId) {
            $query->where("user_id", $userId)->whereOr("send_to", $userId);
        })->delete();
        Db::name("im_online_status")->where("appid", $appid)->where(function($query) use ($userId, $uid) {
            $query->where("user_id", $userId)->whereOr("uid", $uid);
        })->delete();
        Db::name("online_record")->where("appid", $appid)->where("userid", $userId)->delete();
        Db::name("user_login_session")->where("appid", $appid)->where("user_id", $userId)->delete();
        Db::name("file")->where("appid", $appid)->where("uploader_id", $userId)->where("uploader", 1)->delete();

        try {
            (new \app\common\tool\WukongIM())->forceDeviceQuit($uid);
        } catch (\Exception $e) {}
    }
    // blin-user-delete-cleanup-end
'''

NEW_DEL_METHOD = r'''
    public function del()
    {
        if (Request::isAjax()) {
            $id = explode(",", input('id'));
            $deleted = 0;
            Db::startTrans();
            try {
                foreach ($id as $key => $value) {
                    $value = intval($value);
                    if ($value <= 0) continue;
                    $user = Db::name("user")->where("id", "=", $value)->lock(true)->find();
                    if (!$user) continue;
                    $this->blinRequireApp($user["appid"]);
                    $this->blinUserDeleteCleanup($user);
                    Db::name("comments")->where("userid", "=", $value)->delete();
                    Db::name("forum_posts")->where("userid", "=", $value)->delete();
                    Db::name("apps")->where("userid", "=", $value)->delete();
                    Db::name("apps_comments")->where("userid", "=", $value)->delete();
                    Db::name("apps_payment")->where("userid", "=", $value)->delete();
                    Db::name("notes")->where("userid", "=", $value)->delete();
                    Db::name("operation_log")->where("uid", "=", $value)->delete();
                    Db::name("order_records")->where("userid", "=", $value)->delete();
                    Db::name("polymorphic")->where("userid = {$value} and (type = 1 or type = 2 or type = 5)")->delete();
                    Db::name("polymorphic")->where("other_id = {$value}")->delete();
                    Db::name("post_payment")->where("userid", "=", $value)->delete();
                    Db::name("report")->where("uid", "=", $value)->delete();
                    Db::name("sign_record")->where("userid", "=", $value)->delete();
                    Db::name("transaction_statement")->where("userid", "=", $value)->delete();
                    Db::name("user_information_review")->where("userid", "=", $value)->delete();
                    Db::name("user_log")->where("userid", "=", $value)->delete();
                    Db::name("withdrawal_record")->where("userid", "=", $value)->delete();
                    Db::name("user")->where("id", "=", $value)->delete();
                    $deleted++;
                }
                Db::commit();
                return $this->success("删除成功，已同步清理相关聊天、群聊、好友、红包、转账和通知记录", '', ["deleted"=>$deleted]);
            } catch (\Exception $e) {
                try { Db::rollback(); } catch (\Exception $rollbackException) {}
                return $this->error("删除失败：" . $e->getMessage());
            }
        }
    }
'''


def backup(path: Path) -> None:
    if not path.exists():
        return
    stamp = datetime.now().strftime("%Y%m%d%H%M%S")
    shutil.copy2(path, path.with_name(f"{path.name}.bak_user_delete_cleanup_{stamp}"))


def strip_block(source: str, start: str, end: str) -> str:
    pattern = re.compile(r"\n?\s*" + re.escape(start) + r".*?" + re.escape(end) + r"\n?", re.S)
    return pattern.sub("\n", source)


def replace_method(source: str, name: str, body: str) -> str:
    pattern = re.compile(r"\n\s*public function " + re.escape(name) + r"\s*\([^)]*\)\s*\{", re.M)
    match = pattern.search(source)
    if not match:
        raise RuntimeError(f"missing method {name}")
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


def patch_user_controller() -> None:
    source = USER_CONTROLLER.read_text(encoding="utf-8", errors="ignore")
    updated = strip_block(source, "// blin-user-delete-cleanup-start", "// blin-user-delete-cleanup-end")
    updated = updated.replace("    //删除用户\n\n    //删除用户\n", "    //删除用户\n")
    marker = "    //删除用户\n    public function del()"
    if marker not in updated:
        raise RuntimeError("missing user delete marker")
    updated = updated.replace(marker, HELPER_BLOCK.rstrip() + "\n\n" + marker, 1)
    updated = replace_method(updated, "del", NEW_DEL_METHOD)
    if updated != source:
        backup(USER_CONTROLLER)
        USER_CONTROLLER.write_text(updated, encoding="utf-8")


def main() -> None:
    patch_user_controller()
    print("PATCHED_USER_DELETE_CLEANUP")


if __name__ == "__main__":
    main()
