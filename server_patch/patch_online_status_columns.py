from pathlib import Path
p = Path('/www/wwwroot/blinlin/application/api/controller/Api.php')
s = p.read_text()
backup = p.with_suffix('.php.bak_online_status_columns_20260608')
backup.write_text(s)
needle = '''                try { Db::execute("ALTER TABLE `mr_im_online_status` ADD COLUMN `device` varchar(32) NOT NULL DEFAULT ''"); } catch (\\Exception $e) {}
                try { Db::execute("ALTER TABLE `mr_im_online_status` ADD COLUMN `platform` varchar(32) NOT NULL DEFAULT ''"); } catch (\\Exception $e) {}
                try { Db::execute("ALTER TABLE `mr_im_online_status` ADD COLUMN `terminal` varchar(32) NOT NULL DEFAULT ''"); } catch (\\Exception $e) {}
                try { Db::execute("ALTER TABLE `mr_im_online_status` ADD COLUMN `device_flag` int(11) NOT NULL DEFAULT 0"); } catch (\\Exception $e) {}
'''
replacement = '''                try { Db::execute("ALTER TABLE `mr_im_online_status` ADD COLUMN `last_event` varchar(64) NOT NULL DEFAULT ''"); } catch (\\Exception $e) {}
                try { Db::execute("ALTER TABLE `mr_im_online_status` ADD COLUMN `last_seen` datetime DEFAULT NULL"); } catch (\\Exception $e) {}
                try { Db::execute("ALTER TABLE `mr_im_online_status` ADD COLUMN `raw_data` text"); } catch (\\Exception $e) {}
                try { Db::execute("ALTER TABLE `mr_im_online_status` ADD COLUMN `update_time` datetime DEFAULT NULL"); } catch (\\Exception $e) {}
                try { Db::execute("ALTER TABLE `mr_im_online_status` ADD COLUMN `device` varchar(32) NOT NULL DEFAULT ''"); } catch (\\Exception $e) {}
                try { Db::execute("ALTER TABLE `mr_im_online_status` ADD COLUMN `platform` varchar(32) NOT NULL DEFAULT ''"); } catch (\\Exception $e) {}
                try { Db::execute("ALTER TABLE `mr_im_online_status` ADD COLUMN `terminal` varchar(32) NOT NULL DEFAULT ''"); } catch (\\Exception $e) {}
                try { Db::execute("ALTER TABLE `mr_im_online_status` ADD COLUMN `device_flag` int(11) NOT NULL DEFAULT 0"); } catch (\\Exception $e) {}
'''
if needle not in s:
    raise SystemExit('alter block not found')
s = s.replace(needle, replacement, 1)
p.write_text(s)
print('patched', backup)