from pathlib import Path
import os
import subprocess


API = Path("/www/wwwroot/blinlin/application/api/controller/Api.php")


text = API.read_text()
old = '''        $messageId = Db::name("messages")->insertGetId(["sender_id"=>intval($systemUser["id"]), "receiver_id"=>intval($targetUserId), "content"=>$content, "create_time"=>$now, "message_type"=>0, "is_read"=>0, "is_deleted"=>0, "image_path"=>"", "pid"=>0, "money_type"=>0, "file_path"=>"", "file_name"=>""]);
'''
new = '''        $messageId = Db::name("messages")->insertGetId(["appid"=>intval($this->appid), "sender_id"=>intval($systemUser["id"]), "receiver_id"=>intval($targetUserId), "content"=>$content, "create_time"=>$now, "message_type"=>0, "is_read"=>0, "is_deleted"=>0, "image_path"=>"", "pid"=>0, "money_type"=>0, "file_path"=>"", "file_name"=>""]);
'''
if new in text:
    print("system welcome appid already patched")
elif old in text:
    API.write_text(text.replace(old, new, 1))
    print("system welcome appid patched")
else:
    raise RuntimeError("system welcome insert snippet not found")

sql = r"""
UPDATE mr_messages m
JOIN mr_user su ON su.id=m.sender_id
SET m.appid=su.appid
WHERE (m.appid=0 OR m.appid IS NULL) AND su.appid IS NOT NULL AND su.appid>0;

UPDATE mr_messages m
JOIN mr_user ru ON ru.id=m.receiver_id
SET m.appid=ru.appid
WHERE (m.appid=0 OR m.appid IS NULL) AND ru.appid IS NOT NULL AND ru.appid>0;
"""
db_password = os.environ.get("BLINLIN_DB_PASSWORD")
if not db_password:
    raise RuntimeError("BLINLIN_DB_PASSWORD is required")

subprocess.run(
    ["mysql", "-h127.0.0.1", "-ublinlin", "-p" + db_password, "blinlin"],
    input=sql.encode(),
    check=True,
)
print("legacy private message appid repaired")
