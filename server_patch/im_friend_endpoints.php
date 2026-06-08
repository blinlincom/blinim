<?php
// Blinlin IM friend endpoints patch.
// Adapt include/db/token helpers to your existing backend framework before copy.

function json_success($data = [], $msg = 'success') { echo json_encode(['code'=>1,'msg'=>$msg,'data'=>$data], JSON_UNESCAPED_UNICODE); exit; }
function json_fail($msg) { echo json_encode(['code'=>0,'msg'=>$msg,'data'=>[]], JSON_UNESCAPED_UNICODE); exit; }
function uid_from_token(PDO $pdo, string $token): int {
    // TODO: replace with existing usertoken resolver.
    $stmt = $pdo->prepare('SELECT id FROM users WHERE usertoken=? LIMIT 1');
    $stmt->execute([$token]);
    $id = intval($stmt->fetchColumn());
    if ($id <= 0) json_fail('登录已过期');
    return $id;
}
function friend_exists(PDO $pdo, int $uid, int $fid): bool {
    $stmt = $pdo->prepare('SELECT 1 FROM im_friends WHERE user_id=? AND friend_id=? AND status=1 LIMIT 1');
    $stmt->execute([$uid, $fid]);
    return (bool)$stmt->fetchColumn();
}

$action = $_GET['action'] ?? $_POST['action'] ?? '';
$token = $_POST['usertoken'] ?? '';
$uid = uid_from_token($pdo, $token);

if ($action === 'search_user') {
    $kw = trim($_POST['keyword'] ?? '');
    if ($kw === '') json_success(['list'=>[]]);
    $stmt = $pdo->prepare('SELECT id,username,nickname,usertx FROM users WHERE username=? OR id=? LIMIT 20');
    $stmt->execute([$kw, intval($kw)]);
    json_success(['list'=>$stmt->fetchAll(PDO::FETCH_ASSOC)]);
}

if ($action === 'get_friends') {
    $stmt = $pdo->prepare('SELECT u.id,u.username,u.nickname,u.usertx FROM im_friends f JOIN users u ON u.id=f.friend_id WHERE f.user_id=? AND f.status=1 ORDER BY f.updated_at DESC');
    $stmt->execute([$uid]);
    json_success(['list'=>$stmt->fetchAll(PDO::FETCH_ASSOC)]);
}

if ($action === 'is_friend') {
    $fid = intval($_POST['friend_id'] ?? $_POST['user_id'] ?? 0);
    json_success(['is_friend'=>friend_exists($pdo, $uid, $fid) ? 1 : 0]);
}

if ($action === 'add_friend' || $action === 'apply_friend') {
    $fid = intval($_POST['friend_id'] ?? $_POST['user_id'] ?? 0);
    $message = trim($_POST['message'] ?? '');
    if ($fid <= 0 || $fid === $uid) json_fail('用户不存在');
    $pdo->beginTransaction();
    $stmt = $pdo->prepare('INSERT INTO im_friend_requests(from_user_id,to_user_id,message,status) VALUES(?,?,?,0) ON DUPLICATE KEY UPDATE message=VALUES(message),updated_at=NOW()');
    $stmt->execute([$uid, $fid, $message]);
    // Current product uses direct add; switch to request-only by removing the two inserts below.
    $stmt = $pdo->prepare('INSERT INTO im_friends(user_id,friend_id,status) VALUES(?,?,1) ON DUPLICATE KEY UPDATE status=1,updated_at=NOW()');
    $stmt->execute([$uid, $fid]);
    $stmt->execute([$fid, $uid]);
    $pdo->commit();
    json_success([], '添加好友成功');
}

if ($action === 'send_message_guard') {
    $receiverId = intval($_POST['receiver_id'] ?? 0);
    $messageType = intval($_POST['message_type'] ?? 0);
    if (!friend_exists($pdo, $uid, $receiverId)) {
        if ($messageType !== 0) json_fail('非好友只能发送文字消息');
        $stmt = $pdo->prepare('SELECT COUNT(*) FROM messages WHERE sender_id=? AND receiver_id=? AND message_type=0');
        $stmt->execute([$uid, $receiverId]);
        if (intval($stmt->fetchColumn()) >= 3) json_fail('非好友最多只能发送三条文字消息');
    }
    json_success([], '允许发送');
}

json_fail('未知接口');