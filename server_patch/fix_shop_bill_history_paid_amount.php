<?php
require __DIR__ . '/../thinkphp/base.php';

\think\Container::get('app')->path(__DIR__ . '/../application/')->initialize();

function blin_money_text($value)
{
    $text = number_format(floatval($value), 2, '.', '');
    return rtrim(rtrim($text, '0'), '.');
}

function blin_signed_money_text($value)
{
    return '-' . blin_money_text($value);
}

$orders = \think\Db::name('order_records')
    ->where('status', 1)
    ->where('payment_method', 'in', '0,1')
    ->where('total_amount', '>', 0)
    ->where('received_quantity', '>', 0)
    ->order('id asc')
    ->select();

$fixed = 0;
$skipped = 0;
$touchedBills = [];

foreach ($orders as $order) {
    $paid = round(floatval($order['total_amount']), 2);
    $received = round(floatval($order['received_quantity']), 2);
    if ($paid <= 0 || $received <= 0 || abs($paid - $received) < 0.005) {
        continue;
    }

    $paidType = intval($order['payment_method']) === 1 ? 1 : 0;
    $baseTime = strtotime(isset($order['payment_time']) ? $order['payment_time'] : '');
    if (!$baseTime) {
        $baseTime = strtotime(isset($order['create_time']) ? $order['create_time'] : '');
    }
    if (!$baseTime) {
        $skipped++;
        continue;
    }

    $start = date('Y-m-d H:i:s', $baseTime - 900);
    $end = date('Y-m-d H:i:s', $baseTime + 900);
    $rows = \think\Db::name('transaction_statement')
        ->where('appid', intval($order['appid']))
        ->where('userid', intval($order['userid']))
        ->where('transaction_type', 3)
        ->where('type', $paidType)
        ->where('remark', 'like', '购买商品%')
        ->where('transaction_amount', 'like', '-%')
        ->where('transaction_date', 'between', [$start, $end])
        ->order('id asc')
        ->select();

    $best = null;
    $bestDiff = PHP_INT_MAX;
    foreach ($rows as $row) {
        $billId = intval($row['id']);
        if (isset($touchedBills[$billId])) {
            continue;
        }
        $oldAbs = abs(floatval($row['transaction_amount']));
        if (abs($oldAbs - $received) >= 0.005) {
            continue;
        }
        $rowTime = strtotime($row['transaction_date']);
        $diff = $rowTime ? abs($rowTime - $baseTime) : 0;
        if ($best === null || $diff < $bestDiff) {
            $best = $row;
            $bestDiff = $diff;
        }
    }

    if ($best === null) {
        $skipped++;
        continue;
    }

    \think\Db::name('transaction_statement')->where('id', intval($best['id']))->update([
        'transaction_amount' => blin_signed_money_text($paid),
        'type' => $paidType,
    ]);
    $touchedBills[intval($best['id'])] = true;
    $fixed++;
}

echo "FIXED {$fixed}\n";
echo "SKIPPED {$skipped}\n";
