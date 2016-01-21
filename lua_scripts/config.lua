mysql_config = {
    host = "cobar.sre.internal.nosa.me,
    port = 8066,
    database = "DATABASE",
    user = "USER",
    password = "PASSWORD",
    max_packet_size = 1024 * 1000,
    max_conn_per_worker = 10,
    max_conn_timeout_ms = 10000,
}

if mtsql_config ~= nil then
    ngx.log(ngx.WARN, "load db_config from config.lua succeed")
end
