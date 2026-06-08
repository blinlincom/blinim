from pathlib import Path
from datetime import datetime
p = Path('/www/wwwroot/blinlin/application/api/controller/Api.php')
s = p.read_text()
backup = p.with_name('Api.php.bak_friend_notify_status_' + datetime.now().strftime('%Y%m%d%H%M%S'))
backup.write_text(s)
old_reject = 'Db::table("im_friend_requests")->where("id", $request["id"])->update(["status"=>2,"updated_at"=>$now]);\n            $this->json(1, "已拒绝好友申请");'
new_reject = 'Db::table("im_friend_requests")->where("id", $request["id"])->update(["status"=>2,"updated_at"=>$now]);\n            Db::name("message_notification")->where("user_id", $user_all_info["id"])->where("postid", $from_user_id)->where("type", 20)->update(["content"=>"已拒绝该好友申请","status"=>1]);\n            $this->json(1, "已拒绝好友申请");'
old_accept = 'Db::table("im_friend_requests")->where("id", $request["id"])->update(["status"=>1,"updated_at"=>$now]);\n        Db::table("im_friends")->insert(["user_id"=>$user_all_info["id"],"friend_id"=>$from_user_id,"status"=>1,"created_at"=>$now,"updated_at"=>$now], true);'
new_accept = 'Db::table("im_friend_requests")->where("id", $request["id"])->update(["status"=>1,"updated_at"=>$now]);\n        Db::name("message_notification")->where("user_id", $user_all_info["id"])->where("postid", $from_user_id)->where("type", 20)->update(["content"=>"已通过该好友申请","status"=>1]);\n        Db::table("im_friends")->insert(["user_id"=>$user_all_info["id"],"friend_id"=>$from_user_id,"status"=>1,"created_at"=>$now,"updated_at"=>$now], true);'
if old_reject not in s or old_accept not in s:
    raise SystemExit('target status lines not found')
s = s.replace(old_reject, new_reject).replace(old_accept, new_accept)
p.write_text(s)
print('patched', backup)