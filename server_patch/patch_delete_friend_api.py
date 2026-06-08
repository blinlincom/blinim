from pathlib import Path
from datetime import datetime
p = Path('/www/wwwroot/blinlin/application/api/controller/Api.php')
s = p.read_text()
if 'public function delete_friend()' in s:
    print('delete_friend already exists')
else:
    backup = p.with_name('Api.php.bak_delete_friend_' + datetime.now().strftime('%Y%m%d%H%M%S'))
    backup.write_text(s)
    marker = '    //处理好友申请\n    public function handle_friend_request()'
    start = s.find(marker)
    if start < 0:
        raise SystemExit('handle_friend_request marker not found')
    code = r'''    //删除好友
    public function delete_friend()
    {
        $user_all_info = $this->user_info;
        $friend_id = intval(input("friend_id") ?: input("user_id"));
        if ($friend_id <= 0 || $friend_id == $user_all_info["id"]) {
            $this->json(0, "用户不存在");
        }
        Db::table("im_friends")->where("user_id", $user_all_info["id"])->where("friend_id", $friend_id)->update(["status"=>0,"updated_at"=>date("Y-m-d H:i:s")]);
        Db::table("im_friends")->where("user_id", $friend_id)->where("friend_id", $user_all_info["id"])->update(["status"=>0,"updated_at"=>date("Y-m-d H:i:s")]);
        $this->json(1, "已删除好友");
    }
    public function remove_friend()
    {
        return $this->delete_friend();
    }
    public function del_friend()
    {
        return $this->delete_friend();
    }
'''
    s = s[:start] + code + s[start:]
    p.write_text(s)
    print('patched', backup)