local os = require "os"
local str = require "resty.string"
local resty_md5 = require "resty.md5"
local upload = require "resty.upload"
local helper = require "helper"
local cjson = require "cjson"
local utils = require "utils"

local arg_names = {"name", "target_filename", "branch", "idc"}

function err_exit (err, code) 
    ngx.log(ngx.ERR, err)
    ngx.exit(code)
end

function save_into_mysql(db, req_args, url, md5_sum)
    local data = {}
    for _, arg_name in ipairs(arg_names) do
        local raw = req_args[arg_name]
        if raw == nil then
            return error("can't find essential arg " .. arg_name .. " in request arguments")
        end
        local value = ngx.unescape_uri(raw)
        data[arg_name] = value
    end
    data['url'] = url
    data['md5'] = md5_sum
    data['ctime'] = os.date("%Y%m%d%H%M%S")
    ngx.log(ngx.NOTICE, "data: " .. cjson.encode(data))
    local raw_sql = "insert into packages (name, target_filename, branch, idc, ctime, url, md5) " ..
        "values ({{name}}, {{target_filename}}, {{branch}}, {{idc}}, {{ctime}}, {{url}}, {{md5}})"
    local sql = string.gsub(raw_sql, "{{(.-)}}", function (key) return ngx.quote_sql_str(data[key]) end)
    ngx.log(ngx.NOTICE, "sql: " .. sql)
    res, err, errno, sqlstate = db:query(sql)
    if err ~= nil then
        return err
    end
    return 
end


if (helper == nil or utils == nil) then
    err_exit("not find helper/utils lib", 500)
    return
end


local chunk_size = 4096
local form, err = upload:new(chunk_size)
if not form then
    err_exit("failed to new upload: " .. err, 500)
end
local md5 = resty_md5:new()
local file
local tmp = {}
local ret = {}

while true do
    local typ, res, err = form:read()

    if not typ then
        ngx.say("failed to read: ", err)
        if file then
	    file:close()
	    file = nil
        end
        break
    end

    if typ == "header" then
        if #res == 3 and res[1] == "Content-Disposition" then
            local file_name = helper.find_filename(res)
            if file_name then
                local path = "/mfs/" .. file_name
                file = io.open(path, "w+")
                if not file then
                    ngx.say("failed to open file ", file_name)
                    break
                else
                    tmp[file] = file_name 
                end
            end
        end

    elseif typ == "body" then
        if file then
            file:write(res)
            md5:update(res)
        end

    elseif typ == "part_end" then
        local md5_sum = str.to_hex(md5:final())
	local filename = tmp[file]
        local url = "http://download.hy01.nosa.me/download/" .. filename
        if file then
            table.insert(ret, {url=url, md5=md5_sum})
            tmp[file] = nil
            file:close()
        end

        local db, err = utils.mysql_init(mysql_config)
        if err ~= nil then
            return err_exit("mysql init fail: " .. err, 503)
        end

        local args = ngx.req.get_uri_args()
        local err = save_into_mysql(db, args, filename, md5_sum)

        if err ~= nil then
    	    utils.mysql_close(db)
            err_exit("save package info to mysql fail: " .. err, 503)
        end

        file = nil
        md5:reset()

    elseif typ == "eof" then
	if file then
	    file:close()
            file = nil
        end
        utils.mysql_close(db)
        ngx.say(cjson.encode(ret))
        ret = nil
        break

    else
	if file then
	    file:close()
            file = nil
        end
    end
end
