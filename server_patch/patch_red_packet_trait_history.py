#!/usr/bin/env python3
"""Backfill red-packet state in routed group chat history."""
from datetime import datetime
from pathlib import Path


ROOT = Path("/www/wwwroot/blinlin")
TRAIT = ROOT / "application/api/controller/traits/ImApiTrait.php"


def backup(path: Path, suffix: str) -> str:
    target = path.with_name(
        f"{path.name}.bak_{suffix}_{datetime.now().strftime('%Y%m%d%H%M%S')}"
    )
    target.write_text(path.read_text(errors="ignore"))
    return str(target)


HELPERS = r'''
    // blin-red-packet-trait-history
    private function blinTraitRedPacketMoneyText($value)
    {
        return number_format(floatval($value), 2, ".", "");
    }

    private function blinTraitRedPacketStatusText($status)
    {
        $status = intval($status);
        if ($status == 1) return "finished";
        if ($status == 2) return "refunded";
        return "pending";
    }

    private function blinTraitRedPacketContent($message, $viewerId)
    {
        $payload = json_decode(strval(isset($message['payload']) ? $message['payload'] : ''), true);
        $content = is_array($payload) && isset($payload['content']) && is_array($payload['content']) ? $payload['content'] : [];
        try {
            $order = Db::name('im_red_packet_order')
                ->where('appid', intval($this->appid))
                ->where('group_message_id', intval($message['id']))
                ->find();
            if (!$order) return $content;
            $claimedCount = max(0, intval($order['total_count']) - intval($order['remaining_count']));
            $claim = Db::name('im_red_packet_claim')
                ->where('appid', intval($this->appid))
                ->where('red_packet_id', intval($order['id']))
                ->where('user_id', intval($viewerId))
                ->find();
            return array_merge($content, [
                'red_packet_id' => intval($order['id']),
                'message_id' => intval($order['message_id']),
                'group_message_id' => intval($order['group_message_id']),
                'client_msg_no' => strval($order['client_msg_no']),
                'sender_id' => intval($order['sender_id']),
                'group_id' => intval($order['group_id']),
                'channel_type' => 2,
                'scope' => 'group',
                'packet_type' => strval($order['packet_type']),
                'packet_type_label' => strval($order['packet_type']) === 'lucky' ? '拼手气红包' : '普通红包',
                'amount' => $this->blinTraitRedPacketMoneyText($order['amount']),
                'total_amount' => $this->blinTraitRedPacketMoneyText($order['amount']),
                'remaining_amount' => $this->blinTraitRedPacketMoneyText($order['remaining_amount']),
                'total_count' => intval($order['total_count']),
                'count' => intval($order['total_count']),
                'remaining_count' => intval($order['remaining_count']),
                'claimed_count' => $claimedCount,
                'money_type' => intval($order['money_type']),
                'greeting' => strval($order['greeting']),
                'text' => '[红包] ' . strval($order['greeting']),
                'status' => $this->blinTraitRedPacketStatusText($order['status']),
                'expires_at' => intval($order['expire_time']) > 0 ? date('Y-m-d H:i:s', intval($order['expire_time'])) : '',
                'expire_time' => intval($order['expire_time']),
                'claimed_by_me' => $claim ? 1 : 0,
                'my_claim_amount' => $claim ? $this->blinTraitRedPacketMoneyText($claim['amount']) : '',
            ]);
        } catch (\Exception $e) {
            return $content;
        }
    }

'''


def main() -> None:
    source = TRAIT.read_text(errors="ignore")
    original = source
    if "blinTraitRedPacketContent" not in source:
        marker = "    public function send_im_group_message()\n"
        if marker not in source:
            raise SystemExit("TRAIT_SEND_METHOD_MARKER_NOT_FOUND")
        source = source.replace(marker, HELPERS + marker, 1)
    if "blinTraitRedPacketContent($r" not in source:
        marker = '''                    if (isset($decoded['content']) && is_array($decoded['content'])) {
                        $decoded['content']['nickname'] = $senderName;
                        $decoded['content']['avatar'] = $senderAvatar;
                    }
'''
        replacement = marker + '''                    if (isset($decoded['msg_type']) && strval($decoded['msg_type']) === 'red_packet') {
                        $decoded['content'] = array_merge($this->blinTraitRedPacketContent($r, intval($user['id'])), ['nickname'=>$senderName, 'avatar'=>$senderAvatar]);
                    }
'''
        if marker not in source:
            raise SystemExit("TRAIT_HISTORY_CONTENT_MARKER_NOT_FOUND")
        source = source.replace(marker, replacement, 1)
    if source == original:
        print("RED_PACKET_TRAIT_HISTORY_ALREADY_PRESENT")
        return
    print("PATCH_ImApiTrait.php_BACKUP", backup(TRAIT, "red_packet_trait_history"))
    TRAIT.write_text(source)
    print("PATCHED_RED_PACKET_TRAIT_HISTORY")


if __name__ == "__main__":
    main()
