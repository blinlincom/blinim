# Dynamic key IM connect recovery

Applied on server:

`/www/wwwroot/blinlin/application/api/controller/BaseController.php`

Change both dynamic-key-expired exits in `blinRequestGuard()` from encrypted
`json()` responses to plain JSON:

```php
$this->blinPlainJson(0, "动态密钥已失效，请重新打开应用");
```

Reason: when a request carries an expired or mismatched dynamic key, the server
does not have the request AES key yet. Returning that error through `json()` can
encrypt it with the static app key, which the client cannot decrypt with the
runtime key used for the request. The client then reports a generic decode
failure and IM connect never reaches WuKongIM.

Verification:

- `php -l /www/wwwroot/blinlin/application/api/controller/BaseController.php`
- `/api/get_im_connect_info` with a valid token returns `uid`, `tcp_addr`, and
  `ws_addr`.
- `/api/get_im_connect_info` with an invalid runtime appkey returns readable
  JSON: `{"code":0,"msg":"动态密钥已失效，请重新打开应用",...}`.
