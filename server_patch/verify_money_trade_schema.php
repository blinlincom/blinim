<?php
namespace think;

require __DIR__ . '/thinkphp/base.php';
Container::get('app')->path(__DIR__ . '/application/')->initialize();

use think\Db;

function add_column_if_missing($table, $column, $sql)
{
    try {
        $row = Db::query("SHOW COLUMNS FROM `" . $table . "` LIKE '" . $column . "'");
        if (!$row) {
            Db::execute($sql);
            echo "added {$table}.{$column}\n";
        }
    } catch (\Exception $e) {
        echo "skip {$table}.{$column}: " . $e->getMessage() . "\n";
    }
}

function add_key_if_missing($sql, $label)
{
    try {
        Db::execute($sql);
        echo "added {$label}\n";
    } catch (\Exception $e) {
        echo "skip {$label}\n";
    }
}

function trade_no($prefix, $appid, $id, $time)
{
    $time = intval($time) > 0 ? intval($time) : time();
    return $prefix . str_pad(strval(intval($appid) % 10000), 4, '0', STR_PAD_LEFT) . date('YmdHis', $time) . str_pad(strval(intval($id)), 8, '0', STR_PAD_LEFT);
}

add_column_if_missing('mr_im_transfer_order', 'trade_no', "ALTER TABLE `mr_im_transfer_order` ADD COLUMN `trade_no` varchar(64) NOT NULL DEFAULT '' AFTER `client_msg_no`");
add_column_if_missing('mr_im_transfer_order', 'refund_source', "ALTER TABLE `mr_im_transfer_order` ADD COLUMN `refund_source` varchar(32) NOT NULL DEFAULT '' AFTER `refund_time`");
add_column_if_missing('mr_im_transfer_order', 'refund_operator', "ALTER TABLE `mr_im_transfer_order` ADD COLUMN `refund_operator` varchar(64) NOT NULL DEFAULT '' AFTER `refund_source`");
add_column_if_missing('mr_im_red_packet_order', 'trade_no', "ALTER TABLE `mr_im_red_packet_order` ADD COLUMN `trade_no` varchar(64) NOT NULL DEFAULT '' AFTER `client_msg_no`");
add_column_if_missing('mr_im_red_packet_order', 'refund_source', "ALTER TABLE `mr_im_red_packet_order` ADD COLUMN `refund_source` varchar(32) NOT NULL DEFAULT '' AFTER `refund_time`");
add_column_if_missing('mr_im_red_packet_order', 'refund_operator', "ALTER TABLE `mr_im_red_packet_order` ADD COLUMN `refund_operator` varchar(64) NOT NULL DEFAULT '' AFTER `refund_source`");

add_key_if_missing("ALTER TABLE `mr_im_transfer_order` ADD KEY `idx_trade_no` (`appid`,`trade_no`)", 'transfer idx_trade_no');
add_key_if_missing("ALTER TABLE `mr_im_red_packet_order` ADD KEY `idx_trade_no` (`appid`,`trade_no`)", 'red_packet idx_trade_no');

$transferRows = Db::name('im_transfer_order')->where('trade_no', '')->limit(1000)->select();
foreach (($transferRows ?: []) as $row) {
    Db::name('im_transfer_order')->where('id', intval($row['id']))->where('trade_no', '')->update([
        'trade_no' => trade_no('TR', $row['appid'], $row['id'], $row['create_time']),
    ]);
}
echo "transfer backfilled: " . count($transferRows ?: []) . "\n";

$redPacketRows = Db::name('im_red_packet_order')->where('trade_no', '')->limit(1000)->select();
foreach (($redPacketRows ?: []) as $row) {
    Db::name('im_red_packet_order')->where('id', intval($row['id']))->where('trade_no', '')->update([
        'trade_no' => trade_no('RP', $row['appid'], $row['id'], $row['create_time']),
    ]);
}
echo "red packet backfilled: " . count($redPacketRows ?: []) . "\n";

$checks = [
    'transfer' => Db::query("SHOW COLUMNS FROM `mr_im_transfer_order` WHERE Field IN ('trade_no','refund_source','refund_operator')"),
    'red_packet' => Db::query("SHOW COLUMNS FROM `mr_im_red_packet_order` WHERE Field IN ('trade_no','refund_source','refund_operator')"),
];
echo json_encode($checks, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT) . "\n";
