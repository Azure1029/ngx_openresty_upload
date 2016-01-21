local cjson = require "cjson"
function err_exit (msg, log_msg, code) 
    ngx.log(ngx.ERR, log_msg)
    ngx.exit(code)
end

function mysql_err (err, errno, sqlstate) 
    local errno_msg = errno and errno or "nil"
    local sqlstate_msg = sqlstate and sqlstate or "nil"
    local err_log = err .. ": " .. errno_msg .. ":" .. sqlstate_msg .. "."
    err_exit("bad things happended", err_log, 503)
end

function mysql_close (db)
    if db ~= nil then
        local ok, err = db:set_keepalive(10000, db_config.max_conn_per_worker)
        if err ~= nil then
            ngx.log(ngx.ERR, "set keepalive on db fail: " .. err)
        end
    end
end

local mysql = require "resty.mysql"
local db, err = mysql:new()
if not db then
    err_exit("bad things happended", err, 503)
    return
end

db:set_timeout(1000)

local ok, err, errno, sqlstate = db:connect(db_config)

if not ok then
    mysql_err(err, errno, sqlstate)
    return
end

ngx.log(ngx.INFO, "connected to mysql.")
local args = ngx.req.get_uri_args()
local raw_keyword = args["id"]
if raw_keyword == nil then
    mysql_close(db)
    err_exit("require get args id", "id is nil", 400)
    return
end

local keyword = ngx.quote_sql_str(ngx.unescape_uri(raw_keyword))
ngx.log(ngx.INFO, "get query keyword " .. keyword)
res, err, errno, sqlstate = db:query("select url from yourls_url_tmp0619 use index(idx_keyword_url) where keyword = " .. keyword)
-- res, err, errno, sqlstate = db:query("select url from yourls_url where keyword = " .. keyword)
if not res then
    mysql_close(db)
    mysql_err(err, errno, sqlstate)
end

if next(res) == nil then
    mysql_close(db)
    err_exit("not found", "keyword " .. keyword .. "not found in mysql", 404)
    return
end


mysql_close(db)
if res[1]["url"] ~= nil then
    return ngx.redirect(res[1]["url"], 301)
else
    err_exit("not found", "keyword " .. keyword .. "not found in mysql", 404)
    return
end
