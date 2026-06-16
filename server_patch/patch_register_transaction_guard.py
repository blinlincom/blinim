#!/usr/bin/env python3
"""Guard legacy register rollback errors after post-register hooks."""

from datetime import datetime
from pathlib import Path
import shutil


API = Path("/www/wwwroot/blinlin/application/api/controller/Api.php")


def backup(path):
    target = path.with_name(
        "%s.bak_register_guard_%s" % (path.name, datetime.now().strftime("%Y%m%d%H%M%S"))
    )
    shutil.copy2(path, target)
    print("PATCH_BACKUP", target)


def main():
    source = API.read_text()
    marker = '        } catch (\\Exception $th) {\n            Db::rollback();\n'
    start = source.find(marker)
    if start == -1:
        if "rollbackException" in source:
            print("NO_CHANGE", API)
            return
        raise SystemExit("REGISTER_CATCH_NOT_FOUND")
    end = source.find('\n        }\n\n        Cache::rm($this->appid . "register"', start)
    if end == -1:
        raise SystemExit("REGISTER_CATCH_END_NOT_FOUND")
    end += len("\n        }\n")
    new_block = '''        } catch (\\Exception $th) {
            try { Db::rollback(); } catch (\\Exception $rollbackException) {}
            if (isset($user_id) && intval($user_id) > 0 && Db::name("user")->where("appid", $this->appid)->where("id", intval($user_id))->find()) {
                Cache::rm($this->appid . "register" . get_client_ip());
                Cache::rm($this->appid . "mobile_register" . @$data["mobile"]);
                Cache::rm($this->appid . "email_register" . @$data["email"]);
                $this->json(1, "注册成功");
            }
            $this->json(0, "注册失败");
        }
'''
    if source[start:end] == new_block:
        print("NO_CHANGE", API)
        return
    backup(API)
    API.write_text(source[:start] + new_block + source[end:])
    print("PATCHED", API)


if __name__ == "__main__":
    main()
