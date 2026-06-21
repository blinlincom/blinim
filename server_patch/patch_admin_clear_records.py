#!/usr/bin/env python3
"""Add an admin danger action to clear IM chat, transfer, and red packet records."""

from datetime import datetime
from pathlib import Path
import os
import re
import shutil


ROOT = Path(os.environ.get("BLIN_ROOT", "/www/wwwroot/blinlin"))
IM_CONTROLLER = ROOT / "application/admin/controller/Im.php"
IM_DASHBOARD_VIEW = ROOT / "application/admin/view/im/dashboard.html"

CONTROLLER_BLOCK = r'''
    // blin-clear-records-start
    private function blinClearRecordScopedAppIds($raw)
    {
        $raw = trim(strval($raw));
        if ($this->blinIsSuperAdmin()) {
            if ($raw === "" || $raw === "all" || $raw === "managed") return [];
            $appid = intval($raw);
            if ($appid <= 0) throw new \Exception("请选择应用");
            $this->blinRequireApp($appid);
            return [$appid];
        }
        $allowed = $this->blinAdminAppIds();
        if (!$allowed) throw new \Exception("当前管理员没有可管理的应用");
        if ($raw !== "" && $raw !== "all" && $raw !== "managed") {
            $appid = intval($raw);
            if ($appid <= 0 || !in_array($appid, $allowed)) throw new \Exception("无权管理该应用");
            return [$appid];
        }
        return $allowed;
    }

    private function blinClearRecordApplyApp($query, $appIds, $field = "appid")
    {
        if (!empty($appIds)) $query->whereIn($field, $appIds);
        return $query;
    }

    private function blinClearRecordApplyWhere($query, $where)
    {
        foreach (($where ?: []) as $item) {
            if (!is_array($item) || count($item) < 2) continue;
            if (count($item) >= 3) {
                $query->where($item[0], $item[1], $item[2]);
            } else {
                $query->where($item[0], $item[1]);
            }
        }
        return $query;
    }

    private function blinClearRecordQuery($table, $appIds, $field = "appid", $rawTable = false, $where = [])
    {
        $query = $rawTable ? Db::table($table) : Db::name($table);
        $this->blinClearRecordApplyApp($query, $appIds, $field);
        $this->blinClearRecordApplyWhere($query, $where);
        return $query;
    }

    private function blinClearRecordCountAndDelete($table, $appIds, $field = "appid", $rawTable = false, $where = [])
    {
        $count = intval($this->blinClearRecordQuery($table, $appIds, $field, $rawTable, $where)->count());
        if ($count > 0) $this->blinClearRecordQuery($table, $appIds, $field, $rawTable, $where)->delete();
        return $count;
    }

    private function blinClearRecordCountOnly($table, $appIds, $field = "appid", $rawTable = false, $where = [])
    {
        return intval($this->blinClearRecordQuery($table, $appIds, $field, $rawTable, $where)->count());
    }

    private function blinClearRecordMoneyField($moneyType)
    {
        return intval($moneyType) == 1 ? "integral" : "money";
    }

    private function blinClearRecordRefundPending($appIds)
    {
        $summary = [
            "transfer_refund_count" => 0,
            "transfer_refund_amount" => 0,
            "red_packet_refund_count" => 0,
            "red_packet_refund_amount" => 0,
        ];
        $transferQuery = Db::name("im_transfer_order")->where("status", 0);
        $this->blinClearRecordApplyApp($transferQuery, $appIds, "appid");
        $transferRows = $transferQuery->select();
        foreach (($transferRows ?: []) as $row) {
            $refund = floatval(isset($row["hold_amount"]) ? $row["hold_amount"] : 0);
            if ($refund <= 0) {
                $refund = floatval(isset($row["amount"]) ? $row["amount"] : 0);
                if (intval(isset($row["fee_payer"]) ? $row["fee_payer"] : 0) == 1) $refund += floatval(isset($row["fee"]) ? $row["fee"] : 0);
            }
            if ($refund <= 0) continue;
            $field = $this->blinClearRecordMoneyField(isset($row["money_type"]) ? $row["money_type"] : 0);
            $user = Db::name("user")->where("appid", intval($row["appid"]))->where("id", intval($row["sender_id"]))->lock(true)->find();
            if (!$user) continue;
            Db::name("user")->where("appid", intval($row["appid"]))->where("id", intval($row["sender_id"]))->update([$field => floatval($user[$field]) + $refund]);
            $summary["transfer_refund_count"]++;
            $summary["transfer_refund_amount"] += $refund;
        }

        $packetQuery = Db::name("im_red_packet_order")->where("status", 0)->where("remaining_amount", ">", 0);
        $this->blinClearRecordApplyApp($packetQuery, $appIds, "appid");
        $packetRows = $packetQuery->select();
        foreach (($packetRows ?: []) as $row) {
            $refund = floatval(isset($row["remaining_amount"]) ? $row["remaining_amount"] : 0);
            if ($refund <= 0) continue;
            $field = $this->blinClearRecordMoneyField(isset($row["money_type"]) ? $row["money_type"] : 0);
            $user = Db::name("user")->where("appid", intval($row["appid"]))->where("id", intval($row["sender_id"]))->lock(true)->find();
            if (!$user) continue;
            Db::name("user")->where("appid", intval($row["appid"]))->where("id", intval($row["sender_id"]))->update([$field => floatval($user[$field]) + $refund]);
            $summary["red_packet_refund_count"]++;
            $summary["red_packet_refund_amount"] += $refund;
        }
        $summary["transfer_refund_amount"] = number_format($summary["transfer_refund_amount"], 2, ".", "");
        $summary["red_packet_refund_amount"] = number_format($summary["red_packet_refund_amount"], 2, ".", "");
        return $summary;
    }

    private function blinClearRecordStats($appIds = [])
    {
        return [
            "private_messages" => $this->blinClearRecordCountOnly("messages", $appIds),
            "group_messages" => $this->blinClearRecordCountOnly("im_group_messages", $appIds),
            "message_logs" => $this->blinClearRecordCountOnly("im_message_log", $appIds),
            "offline_messages" => $this->blinClearRecordCountOnly("im_offline_message", $appIds),
            "call_sessions" => $this->blinClearRecordCountOnly("im_call_sessions", $appIds),
            "call_signals" => $this->blinClearRecordCountOnly("im_call_signals", $appIds),
            "transfers" => $this->blinClearRecordCountOnly("im_transfer_order", $appIds),
            "red_packets" => $this->blinClearRecordCountOnly("im_red_packet_order", $appIds),
            "red_packet_claims" => $this->blinClearRecordCountOnly("im_red_packet_claim", $appIds),
            "money_bills" => $this->blinClearRecordCountOnly("transaction_statement", $appIds, "appid", false, [["transaction_type", "in", [9, 15]]]),
            "money_notifications" => $this->blinClearRecordCountOnly("message_notification", $appIds, "appid", false, [["type", 21]]),
        ];
    }

    private function blinAdminClearAllRecords()
    {
        $confirm = trim(strval(input("confirm")));
        if ($confirm !== "清空记录") return $this->imFail("请输入确认文本：清空记录");
        try {
            $appIds = $this->blinClearRecordScopedAppIds(input("appid"));
            $before = $this->blinClearRecordStats($appIds);
            Db::startTrans();
            $refund = $this->blinClearRecordRefundPending($appIds);
            $deleted = [];
            $deleted["private_messages"] = $this->blinClearRecordCountAndDelete("messages", $appIds);
            $deleted["group_messages"] = $this->blinClearRecordCountAndDelete("im_group_messages", $appIds);
            $deleted["message_logs"] = $this->blinClearRecordCountAndDelete("im_message_log", $appIds);
            $deleted["offline_messages"] = $this->blinClearRecordCountAndDelete("im_offline_message", $appIds);
            $deleted["single_clear_state"] = $this->blinClearRecordCountAndDelete("im_chat_clear_state", $appIds, "appid", true);
            $deleted["group_clear_state"] = $this->blinClearRecordCountAndDelete("im_group_clear_state", $appIds);
            $deleted["group_read_state"] = $this->blinClearRecordCountAndDelete("im_group_read_state", $appIds);
            $deleted["call_sessions"] = $this->blinClearRecordCountAndDelete("im_call_sessions", $appIds);
            $deleted["call_signals"] = $this->blinClearRecordCountAndDelete("im_call_signals", $appIds);
            $deleted["transfer_orders"] = $this->blinClearRecordCountAndDelete("im_transfer_order", $appIds);
            $deleted["red_packet_claims"] = $this->blinClearRecordCountAndDelete("im_red_packet_claim", $appIds);
            $deleted["red_packet_orders"] = $this->blinClearRecordCountAndDelete("im_red_packet_order", $appIds);
            $deleted["money_bills"] = $this->blinClearRecordCountAndDelete("transaction_statement", $appIds, "appid", false, [["transaction_type", "in", [9, 15]]]);
            $deleted["money_notifications"] = $this->blinClearRecordCountAndDelete("message_notification", $appIds, "appid", false, [["type", 21]]);
            Db::commit();
            return $this->imOk("清空完成", "", [
                "scope" => empty($appIds) ? "all" : $appIds,
                "before" => $before,
                "deleted" => $deleted,
                "refund" => $refund,
            ]);
        } catch (\Exception $e) {
            try { Db::rollback(); } catch (\Exception $rollbackException) {}
            return $this->imFail($e->getMessage());
        }
    }
    // blin-clear-records-end
'''

DASHBOARD_DANGER_CARD = r'''
  <div class="card mt-3">
    <header class="card-header">
      <div class="card-title text-danger">危险操作：一键清空业务记录</div>
    </header>
    <div class="card-body">
      <div class="alert alert-warning mb-3">
        会清空聊天记录、通话记录、红包记录、转账记录、相关红包/转账账单与红包/转账通知。不会删除用户、好友、群聊、余额、文件和朋友圈。未领取的转账与红包会先退回发送方余额后再删除记录。
      </div>
      <div class="row">
        <div class="col-md-3 mb-2">
          <label class="form-label">清理应用</label>
          <select class="form-control" id="clear_appid">
            {if $is_super_admin}
            <option value="all">全部应用</option>
            {else}
            <option value="managed">我管理的应用</option>
            {/if}
            {foreach $apps as $app}
            <option value="{$app.appid}">{$app.appname}（{$app.appid}）</option>
            {/foreach}
          </select>
        </div>
        <div class="col-md-4 mb-2">
          <label class="form-label">确认文本</label>
          <input class="form-control" id="clear_confirm" placeholder="输入：清空记录">
        </div>
        <div class="col-md-5 mb-2 d-flex align-items-end">
          <button class="btn btn-danger" id="clear_all_records_btn" type="button">
            <i class="mdi mdi-delete-alert"></i> 一键清空聊天/红包/转账记录
          </button>
        </div>
      </div>
      <div class="row mt-2">
        <div class="col-md-2 col-6 mb-2"><div class="text-muted">私聊</div><strong>{$cleanup_stats.private_messages}</strong></div>
        <div class="col-md-2 col-6 mb-2"><div class="text-muted">群聊</div><strong>{$cleanup_stats.group_messages}</strong></div>
        <div class="col-md-2 col-6 mb-2"><div class="text-muted">消息日志</div><strong>{$cleanup_stats.message_logs}</strong></div>
        <div class="col-md-2 col-6 mb-2"><div class="text-muted">离线消息</div><strong>{$cleanup_stats.offline_messages}</strong></div>
        <div class="col-md-2 col-6 mb-2"><div class="text-muted">转账</div><strong>{$cleanup_stats.transfers}</strong></div>
        <div class="col-md-2 col-6 mb-2"><div class="text-muted">红包</div><strong>{$cleanup_stats.red_packets}</strong></div>
        <div class="col-md-2 col-6 mb-2"><div class="text-muted">领取记录</div><strong>{$cleanup_stats.red_packet_claims}</strong></div>
        <div class="col-md-2 col-6 mb-2"><div class="text-muted">相关账单</div><strong>{$cleanup_stats.money_bills}</strong></div>
        <div class="col-md-2 col-6 mb-2"><div class="text-muted">相关通知</div><strong>{$cleanup_stats.money_notifications}</strong></div>
        <div class="col-md-2 col-6 mb-2"><div class="text-muted">通话记录</div><strong>{$cleanup_stats.call_sessions}</strong></div>
      </div>
    </div>
  </div>
'''

DASHBOARD_JS = r'''
<script>
window.parent.$("#iframe-content .mt-nav-bar").find('a.active').text("IM概览");
$("#clear_all_records_btn").click(function(){
  var appid = $("#clear_appid").val();
  var confirmText = $("#clear_confirm").val();
  if(confirmText !== "清空记录"){
    alert("请输入确认文本：清空记录");
    return;
  }
  if(!confirm("确认执行一键清空？该操作不可恢复。")){
    return;
  }
  var loading = $('body').lyearloading ? $('body').lyearloading({opacity:0.2, spinnerSize:'lg'}) : null;
  $.post("{:url('dashboard')}", {op:"clear_all_records", appid:appid, confirm:confirmText}, function(res){
    if(loading) loading.destroy();
    alert(res && res.msg ? res.msg : "操作完成");
    if(res && res.code == 1){ window.location.reload(); }
  }, "json").fail(function(xhr){
    if(loading) loading.destroy();
    alert((xhr && xhr.responseText) ? xhr.responseText : "清空失败");
  });
});
</script>
'''


def backup(path: Path) -> None:
    if not path.exists():
        return
    stamp = datetime.now().strftime("%Y%m%d%H%M%S")
    shutil.copy2(path, path.with_name(f"{path.name}.bak_clear_records_{stamp}"))


def strip_block(source: str, start: str, end: str) -> str:
    pattern = re.compile(r"\n?\s*" + re.escape(start) + r".*?" + re.escape(end) + r"\n?", re.S)
    return pattern.sub("\n", source)


def patch_controller() -> None:
    source = IM_CONTROLLER.read_text(encoding="utf-8", errors="ignore")
    updated = strip_block(source, "// blin-clear-records-start", "// blin-clear-records-end")
    marker = "    // blin-money-records-start\n"
    if marker not in updated:
        raise RuntimeError("missing controller insertion marker")
    updated = updated.replace(marker, CONTROLLER_BLOCK.rstrip() + "\n\n" + marker, 1)
    old_dashboard = """    public function dashboard()
    {
        $wkimStatus = ['connz'=>null,'varz'=>null,'error'=>''];
"""
    new_dashboard = """    public function dashboard()
    {
        if (Request::isPost() && trim(input('op')) === 'clear_all_records') {
            return $this->blinAdminClearAllRecords();
        }
        $wkimStatus = ['connz'=>null,'varz'=>null,'error'=>''];
"""
    if "blinAdminClearAllRecords()" not in updated.split("public function dashboard()", 1)[1].split("public function user_manage()", 1)[0]:
        if old_dashboard not in updated:
            raise RuntimeError("missing dashboard action marker")
        updated = updated.replace(old_dashboard, new_dashboard, 1)
    assign_marker = """        $this->assign('config', [
            'enable' => config('wukongim.enable') ? 1 : 0,
            'api_base' => config('wukongim.api_base'),
            'ws_url' => config('wukongim.ws_url'),
            'webhook_token_configured' => config('wukongim.webhook_token') ? 1 : 0,
        ]);
        return $this->fetch();
"""
    assign_replacement = """        $this->assign('config', [
            'enable' => config('wukongim.enable') ? 1 : 0,
            'api_base' => config('wukongim.api_base'),
            'ws_url' => config('wukongim.ws_url'),
            'webhook_token_configured' => config('wukongim.webhook_token') ? 1 : 0,
        ]);
        $dashboardAppIds = $this->blinIsSuperAdmin() ? [] : $this->blinAdminAppIds();
        if (!$this->blinIsSuperAdmin() && !$dashboardAppIds) $dashboardAppIds = [-1];
        $this->assign('cleanup_stats', $this->blinClearRecordStats($dashboardAppIds));
        $this->assign('apps', $this->blinScopedAppList());
        $this->assign('is_super_admin', $this->blinIsSuperAdmin() ? 1 : 0);
        return $this->fetch();
"""
    dashboard_scope = updated.split("public function dashboard()", 1)[1].split("public function user_manage()", 1)[0]
    old_stats = """        $dashboardAppIds = $this->blinIsSuperAdmin() ? [] : $this->blinAdminAppIds();
        $this->assign('cleanup_stats', $this->blinClearRecordStats($dashboardAppIds));
"""
    new_stats = """        $dashboardAppIds = $this->blinIsSuperAdmin() ? [] : $this->blinAdminAppIds();
        if (!$this->blinIsSuperAdmin() && !$dashboardAppIds) $dashboardAppIds = [-1];
        $this->assign('cleanup_stats', $this->blinClearRecordStats($dashboardAppIds));
"""
    if old_stats in dashboard_scope and new_stats not in dashboard_scope:
        updated = updated.replace(old_stats, new_stats, 1)
        dashboard_scope = updated.split("public function dashboard()", 1)[1].split("public function user_manage()", 1)[0]
    if "cleanup_stats" not in dashboard_scope:
        if assign_marker not in updated:
            raise RuntimeError("missing dashboard assign marker")
        updated = updated.replace(assign_marker, assign_replacement, 1)
    if updated != source:
        backup(IM_CONTROLLER)
        IM_CONTROLLER.write_text(updated, encoding="utf-8")


def patch_dashboard_view() -> None:
    source = IM_DASHBOARD_VIEW.read_text(encoding="utf-8", errors="ignore")
    updated = strip_block(source, "<!-- blin-clear-records-view-start -->", "<!-- blin-clear-records-view-end -->")
    card = "\n<!-- blin-clear-records-view-start -->\n" + DASHBOARD_DANGER_CARD.strip() + "\n<!-- blin-clear-records-view-end -->\n"
    insert_marker = "</div>\n{/block}"
    if insert_marker not in updated:
        raise RuntimeError("missing dashboard view insertion marker")
    updated = updated.replace(insert_marker, card + "</div>\n{/block}", 1)
    updated = re.sub(r"\{block name=\"js\"\}.*?\{/block\}", "{block name=\"js\"}" + DASHBOARD_JS + "{/block}", updated, flags=re.S)
    if updated != source:
        backup(IM_DASHBOARD_VIEW)
        IM_DASHBOARD_VIEW.write_text(updated, encoding="utf-8")


def main() -> None:
    patch_controller()
    patch_dashboard_view()
    print("PATCHED_ADMIN_CLEAR_RECORDS")


if __name__ == "__main__":
    main()
