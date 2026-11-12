const path = require("path");
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require("fengari");
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
function setg(name, val) {
  lua.lua_pushstring(L, to_luastring(val));
  lua.lua_setglobal(L, to_luastring(name));
}
setg("ADDON_DIR", process.argv[2]);
setg("TEST_DIR", __dirname.replace(/\\/g, "/"));
setg("TEST_FILTER", process.argv[4] || "");
const fs = require("fs");
lua.lua_newtable(L);
for (const f of fs.readdirSync(process.argv[2])) {
  if (!f.endsWith(".lua")) continue;
  lua.lua_pushstring(L, to_luastring(f));
  lua.lua_pushstring(L, to_luastring(fs.readFileSync(path.join(process.argv[2], f), "utf8")));
  lua.lua_settable(L, -3);
}
lua.lua_setglobal(L, to_luastring("SOURCES"));
lua.lua_pushjsfunction(L, function (L) {
  lua.lua_pushnumber(L, performance.now());
  return 1;
});
lua.lua_setglobal(L, to_luastring("NOW_MS"));
const status = lauxlib.luaL_dofile(L, to_luastring(path.resolve(process.argv[3]).replace(/\\/g, "/")));
if (status !== lua.LUA_OK) {
  console.error("LUA ERROR: " + to_jsstring(lua.lua_tostring(L, -1)));
  process.exit(1);
}
