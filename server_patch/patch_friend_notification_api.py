from pathlib import Path
from datetime import datetime
p = Path('/www/wwwroot/blinlin/application/api/controller/Api.php')
s = p.read_text()
backup = p.with_name('Api.php.bak_friend_notify_' + datetime.now().strftime('%Y%m%d%H%M%S'))
backup.write_text(s)
start = s.find('    //添加好友\n    public function add_friend()')
if start < 0:
    start = s.find('    //添加好友\r\n    public function add_friend()')
if start < 0:
    raise SystemExit('add_friend start not found')
end = s.find('    //修改评论置顶状态', start)
if end < 0:
    raise SystemExit('friend block end not found')
new = r'''    //添加好友申请
    public function add_friend()
    {
        $user_all_info = $this->user_info;
        $friend_id = intval(input("friend_id") ?: input("user_id"));
        if ($friend_id <= 0 || $friend_id == $user_all_info["id"]) {
            $this->json(0, "用户不存在");
        }
        $friend = Db::name("user")->where("id", $friend_id)->where("appid", $this->appid)->find();
        if (!$friend) {
            $this->json(0, "用户不存在");
        }
        $exists = Db::table("im_friends")->where("user_id", $user_all_info["id"])->where("friend_id", $friend_id)->where("status", 1)->find();
        if ($exists) {
            $this->json(1, "已经是好友了");
        }
        $message = input("message") ?: "你好，我想添加你为好友";
        $now = date("Y-m-d H:i:s");
        $request = Db::table("im_friend_requests")->where("from_user_id", $user_all_info["id"])->where("to_user_id", $friend_id)->find();
        if ($request) {
            Db::table("im_friend_requests")->where("id", $request["id"])->update(["message"=>$message,"status"=>0,"updated_at"=>$now]);
        } else {
            Db::table("im_friend_requests")->insert(["from_user_id"=>$user_all_info["id"],"to_user_id"=>$friend_id,"message"=>$message,"status"=>0,"created_at"=>$now,"updated_at"=>$now]);
        }
        Db::name("message_notification")->insert([
            "title" => "好友申请",
            "content" => $user_all_info["nickname"] . " 请求添加你为好友：" . $message,
            "send_to" => 0,
            "appid" => $this->appid,
            "time" => $now,
            "type" => 20,
            "user_id" => $friend_id,
            "postid" => $user_all_info["id"],
        ]);
        $this->json(1, "已发送好友申请");
    }
    public function get_friend_list()
    {
        return $this->get_friends();
    }
    public function apply_friend()
    {
        return $this->add_friend();
    }
    //处理好友申请
    public function handle_friend_request()
    {
        $user_all_info = $this->user_info;
        $from_user_id = intval(input("from_user_id") ?: input("friend_id") ?: input("user_id"));
        $action = input("action") ?: (intval(input("status")) == 2 ? "reject" : "accept");
        if ($from_user_id <= 0 || $from_user_id == $user_all_info["id"]) {
            $this->json(0, "申请用户不存在");
        }
        $request = Db::table("im_friend_requests")->where("from_user_id", $from_user_id)->where("to_user_id", $user_all_info["id"])->find();
        if (!$request) {
            $this->json(0, "好友申请不存在或已处理");
        }
        $now = date("Y-m-d H:i:s");
        if ($action == "reject" || $action == "refuse" || $action == "deny") {
            Db::table("im_friend_requests")->where("id", $request["id"])->update(["status"=>2,"updated_at"=>$now]);
            $this->json(1, "已拒绝好友申请");
        }
        Db::table("im_friend_requests")->where("id", $request["id"])->update(["status"=>1,"updated_at"=>$now]);
        Db::table("im_friends")->insert(["user_id"=>$user_all_info["id"],"friend_id"=>$from_user_id,"status"=>1,"created_at"=>$now,"updated_at"=>$now], true);
        Db::table("im_friends")->insert(["user_id"=>$from_user_id,"friend_id"=>$user_all_info["id"],"status"=>1,"created_at"=>$now,"updated_at"=>$now], true);
        $this->json(1, "已通过好友申请");
    }
    public function friend_request_handle()
    {
        return $this->handle_friend_request();
    }
'''
s = s[:start] + new + s[end:]
p.write_text(s)
print('patched', backup)