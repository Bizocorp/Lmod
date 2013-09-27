--------------------------------------------------------------------------
-- Lmod License
--------------------------------------------------------------------------
--
--  Lmod is licensed under the terms of the MIT license reproduced below.
--  This means that Lua is free software and can be used for both academic
--  and commercial purposes at absolutely no cost.
--
--  ----------------------------------------------------------------------
--
--  Copyright (C) 2008-2013 Robert McLay
--
--  Permission is hereby granted, free of charge, to any person obtaining
--  a copy of this software and associated documentation files (the
--  "Software"), to deal in the Software without restriction, including
--  without limitation the rights to use, copy, modify, merge, publish,
--  distribute, sublicense, and/or sell copies of the Software, and to
--  permit persons to whom the Software is furnished to do so, subject
--  to the following conditions:
--
--  The above copyright notice and this permission notice shall be
--  included in all copies or substantial portions of the Software.
--
--  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
--  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
--  OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
--  NONINFRINGEMENT.  IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
--  BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
--  ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
--  CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
--  THE SOFTWARE.
--
--------------------------------------------------------------------------

--------------------------------------------------------------------------
-- MName: This class manages module names.  It turns out that a module
--        name is more complicated only Lmod started supporting
--        category/name/version style module names.  Lmod automatically
--        figures out what the "name", "full name" and "version" are.
--        The "MT:locationTbl()" knows the 3 components for modules that
--        can be loaded.  On the other hand, "MT:exists()" knows for
--        modules that are already loaded.

--        The problem is when a user gives a module name on the command
--        line.  It can be the short name or the full name.  The trouble
--        is that if the user gives "foo/bar" as a module name, it is
--        quite possible that "foo" is the name and "bar" is the version
--        or "foo/bar" is the short name.  The only way to know is to
--        consult either choice above.
--
--        Yet another problem is that a module that is loaded may not be
--        in the module may not be available to load because the
--        MODULEPATH has changed.  Or if you are loading a module then it
--        must be in the locationTbl.  So clients using this class must
--        specify to the ctor that the name of the module is one that will
--        be loaded or one that has been loaded.
--
--        Another consideration is that Lmod only allows for one "name"
--        to be loaded at a time.

require("strict")
require("utils")
require("inherits")

local M      = {}
local dbg    = require("Dbg"):dbg()
local MT     = require("MT")
local pack   = (_VERSION == "Lua 5.1") and argsPack or table.pack
local posix  = require("posix")
MName        = M
--------------------------------------------------------------------------
-- shorten(): This function allows for taking the name and remove one
--            level at a time.  Lmod rules require that if a module is
--            loaded or available, that the "short" name is either
--            the name given or one level removed.  So checking for
--            a "a/b/c/d" then the short name is either "a/b/c/d" or
--            "a/b/c".  It can't be "a/b" and the version be "c/d".
--            In other words, the "version" can only be one component,
--            not a directory/file.  This function can only be called
--            with level = 0 or 1.

local function shorten(name, level)
   if (level == 0) then
      return name
   end

   local i,j = name:find(".*/")
   j = (j or 0) - 1
   return name:sub(1,j)
end

function M.action(self)
   return self._action
end

--------------------------------------------------------------------------
-- MName:new(): This ctor takes "sType" to lookup in either the
--              locationTbl() or the exists() depending on whether it is
--              "load" for modules to be loaded (available) or it is
--              already loaded.  Knowing the short name it is possible to
--              figure out the version (if one exists).  If the module name
--              doesn't exist then the short name (sn) and version are set 
--              to false.  The last argument is "action".  Normally this
--              argument is nil, which implies the value is "match".  Other
--              choices are "atleast", ...

s_findT = false
function M.new(self, sType, name, action)

   if (not s_findT) then
      local Match   = require("Match")
      local AtLeast = require("AtLeast")
      local Latest  = require("Latest")

      local findT   = {}
      findT["match"]   = Match
      findT["atleast"] = AtLeast
      findT["latest"]  = Latest
      s_findT          = findT
   end

   if (not action) then
      action = masterTbl().latest and "latest" or "match"
   end
   local o = s_findT[action]:create()

   o._sn      = false
   o._version = false
   o._sType   = sType
   o._input   = name
   if (sType == "entryT" ) then
      local t = name
      o._name = t.userName
   else
      name    = (name or ""):gsub("/+$","")  -- remove any trailing '/'
      o._name = name
   end
   o._action  = action
   return o
end

--------------------------------------------------------------------------
-- MName:buildA(...): Return an array of MName objects

function M.buildA(self,sType, ...)
   local arg = pack(...)
   local a = {}

   for i = 1, arg.n do
      local v = arg[i]
      if (type(v) == "string" ) then
         a[#a + 1] = self:new(sType, v)
      elseif (type(v) == "table") then
         a[#a + 1] = v
      end
   end
   return a
end

function M.convert2stringA(self, ...)
   local arg = pack(...)
   local a = {}
   for i = 1, arg.n do
      local v      = arg[i]
      local action = v.action()
      if (action == "match") then
         a[#a+1] = '"' .. v:usrName() .. '"'
      else
         local b = {}
         b[#b+1] = action
         b[#b+1] = '("'
         b[#b+1] = v.sn()
         b[#b+1] = '","'
         b[#b+1] = v.version()
         b[#b+1] = '")'
         a[#a+1] = concatTbl(b,"")
      end
   end

   return a
end

local function lazyEval(self)
   dbg.start("lazyEval(self)")
   local sType = self._sType
   if (sType == "entryT") then
      local t       = self._input
      self._sn      = t.sn
      self._version = extractVersion(t.fullName, t.sn)
      dbg.fini("lazyEval")
      return
   end

   local mt   = MT:mt()
   local name = self._name
   if (sType == "load") then
      for level = 0, 1 do
         local n = shorten(name, level)
         if (mt:locationTbl(n)) then
            self._sn      = n
            break
         end
      end
   else
      for level = 0, 1 do
         local n = shorten(name, level)
         if (mt:exists(n)) then
            self._sn      = n
            self._version = mt:Version(n)
            break
         end
      end
   end

   if (self._sn and not self._version) then
      self._version = extractVersion(self._name, self._sn)
   end
   dbg.fini("lazyEval")
end


--------------------------------------------------------------------------
-- MName:sn(): Return the short name

function M.sn(self)
   if (not self._sn) then
      dbg.start("MName:sn()")
      lazyEval(self)
      dbg.fini("MName:sn")
   end

   return self._sn
end

--------------------------------------------------------------------------
-- MName:usrName(): Return the user specified name.  It could be the
--                  short name or the full name.

function M.usrName(self)
   return self._name
end

--------------------------------------------------------------------------
-- MName:version(): Return the version for the module.  Note that the
--                  version is nil if not known.

function M.version(self)
   if (self._sn and self._sn == self._name) then return end
   if (not self._version) then
      dbg.start("MName:version()")
      lazyEval(self)
      dbg.fini("MName:version")
   end
   return self._version
end

--------------------------------------------------------------------------
-- followDefault(): This local function is used to find a default file
--                  that maybe in symbolic link chain. This returns
--                  the absolute path.

local function followDefault(path)
   if (path == nil) then return nil end
   dbg.start("followDefault(path=\"",path,"\")")
   local attr = lfs.symlinkattributes(path)
   local result = path
   if (attr == nil) then
      result = nil
   elseif (attr.mode == "link") then
      local rl = posix.readlink(path)
      local a  = {}
      local n  = 0
      for s in path:split("/") do
         n = n + 1
         a[n] = s or ""
      end

      a[n] = ""
      local i  = n
      for s in rl:split("/") do
         if (s == "..") then
            i = i - 1
         else
            a[i] = s
            i    = i + 1
         end
      end
      result = concatTbl(a,"/")
   end
   dbg.print("result: ",result,"\n")
   dbg.fini("followDefault")
   return result
end

local searchExtT = { ".lua", ''}

function M.find_exact_match(self, pathA, t)
   dbg.start("MName:find_exact_match(pathA, t)")
   dbg.print("UserName: ", self:usrName(), "\n")
   local found    = false
   local result   = nil
   local fullName = ""
   local modName  = ""
   local sn       = self:sn()
   
   for ii = 1, #pathA do
      local vv    = pathA[ii]
      local mpath = vv.mpath
      local fn    = pathJoin(vv.file, self:version())
      found       = false
      result      = nil

      for i = 1, 2 do
         local v        = searchExtT[i]
         local f        = fn .. v
         local attr     = lfs.attributes(f)
         local readable = posix.access(f,"r")
         
         if (readable and attr and attr.mode == "file") then
            result = f
            found  = true
            break;
         end
      end

      if (found) then
         local _, j = result:find(mpath, 1, true)
         fullName  = result:sub(j+2):gsub("%.lua$","")
         dbg.print("fullName: ",fullName,"\n")
         dbg.print("found:", found, " fn: ",fn,"\n")
         break
      end
   end

   
   if (found) then
      t.fn          = result
      t.modFullName = fullName
      t.modName     = sn
      dbg.print("modName: ",sn," fn: ", result," modFullName: ", fullName,
                " default: ",t.default,"\n")
   end

   dbg.fini("MName:find_exact_match")
   return found
end

searchDefaultT = { "/default", "/.version" }


function M.find_marked_default(self, pathA, t)
   dbg.start("MName:find_marked_default(pathA, t)")
   dbg.print("UserName: ", self:usrName(), "\n")
   local found    = false
   local result   = nil
   local fullName = ""
   local modName  = ""
   local Master   = Master
   local sn       = self:sn()
   
   for ii = 1, #pathA do
      local vv    = pathA[ii]
      local mpath = vv.mpath
      local fn    = pathJoin(vv.file, self:version())
      found       = false
      result      = nil

      for i = 1, 2 do
         local v        = searchDefaultT[i]
         local f        = fn .. v
         local attr     = lfs.attributes(f)
         local readable = posix.access(f,"r")
         
         if (readable and attr and attr.mode == "file") then
            result = f
            if (v == "/default") then
               result    = followDefault(result)
               if (result) then
                  t.default = 1
                  found  = true
                  break;
               end
            elseif (v == "/.version") then
               local vf = Master.versionFile(result)
               if (vf) then
                  local mname = M.new(self, "load", pathJoin(sn, vf))
                  t           = mname:find()
                  t.default   = 1
                  result      = t.fn
                  found       = true
                  break;
               end
            end
         end
      end
      if (found) then
         local _, j = result:find(mpath, 1, true)
         fullName  = result:sub(j+2):gsub("%.lua$","")
         dbg.print("fullName: ",fullName,", fn: ",fn,"\n")
         break
      end
   end

   
   if (found) then
      t.fn          = result
      t.modFullName = fullName
      t.modName     = self:sn()
      dbg.print("modName: ",sn," fn: ", result," modFullName: ", fullName,
                " default: ",t.default,"\n")
   end

   dbg.fini("MName:find_marked_default")
   return found
end

function M.find_latest(self, pathA, t)
   dbg.start("MName:find_latest(pathA, t)")
   dbg.print("UserName: ", self:usrName(), "\n")
   local found     = false
   local result    = nil
   local fullName  = ""
   local modName   = ""
   local Master    = Master
   local sn        = self:sn()
   local lastKey   = ''
   local lastValue = false

   for ii = 1, #pathA do
      local vv    = pathA[ii]
      local mpath = vv.mpath
      local fn    = pathJoin(vv.file, self:version())
      found       = false
      result      = lastFileInDir(fn)
      if (result) then
         local _, j    = result:find(mpath, 1, true)
         fullName      = result:sub(j+2):gsub("%.lua$","")
         local version = extractVersion(fullName, sn)
         local pv      = concatTbl(parseVersion(version),".")
         dbg.print("lastFileInDir mpath: ", mpath," fullName: ",fullName,"\n")
         if (pv > lastKey) then
            lastValue = {fullName = fullName, fn = result, mpath = mpath}
         end
      end
   end

   if (lastValue) then
      found         = true
      t.default     = 1
      t.fn          = lastValue.fn
      t.modFullName = lastValue.fullName
      t.modName     = sn
      dbg.print("modName: ",sn," fn: ", result," modFullName: ", fullName,
                " default: ",t.default,"\n")
   end

   dbg.fini("MName:find_latest")
   return found
end



function M.find(self)
   dbg.start("MName:find(",self:usrName(),")")
   local t        = { fn = nil, modFullName = nil, modName = nil, default = 0}
   local mt       = MT:mt()
   local fullName = ""
   local modName  = ""
   local sn       = self:sn()
   local Master   = Master
   dbg.print("MName:find sn: ",sn,"\n")

   local pathA = mt:locationTbl(sn)
   if (pathA == nil or #pathA == 0) then
      dbg.print("did not find key: \"",sn,"\" in mt:locationTbl()\n")
      dbg.fini("MName:find")
      return t
   end
   
   local found = false
   local stepA = self:steps()
   for i = 1, #stepA do
      local func = stepA[i]
      found      = func(self, pathA, t)
      if (found) then
         break
      end
   end

   dbg.fini("MName:find")
   return t
end


--local searchTbl     = {'.lua', '', '/default', '/.version'}
--local numSearch     = 4
--local numSrchLatest = 2
--
--function M.find(self)
--   dbg.start("MName:find(",self:usrName(),")")
--   local t        = { fn = nil, modFullName = nil, modName = nil, default = 0}
--   local mt       = MT:mt()
--   local fullName = ""
--   local modName  = ""
--   local sn       = self:sn()
--   local Master   = Master
--   dbg.print("MName:find sn: ",sn,"\n")
--
--   -- Get all directories that contain the shortname [[sn]].  If none exist
--   -- then the module does not exist => exit
--
--   local pathA = mt:locationTbl(sn)
--   if (pathA == nil or #pathA == 0) then
--      dbg.print("did not find key: \"",sn,"\" in mt:locationTbl()\n")
--      dbg.fini("MName:find")
--      return t
--   end
--   local fn, result
--
--   -- numS is the number of items to search for.  The first two are standard, the
--   -- next 2 are the default and .version choices.  So if the user specifies
--   -- "--latest" on the command line then set numS to 2 otherwise 4.
--   local numS = (self:action() == "latest") and numSrchLatest or numSearch
--
--   -- Outer Loop search over directories.
--   local found  = false
--   for ii = 1, #pathA do
--      local vv     = pathA[ii]
--      local mpath  = vv.mpath
--      t.default    = 0
--      fn           = pathJoin(vv.file, self:version())
--      result       = nil
--      found        = false
--
--      -- Inner loop search over search choices.
--      for i = 1, numS do
--         local v    = searchTbl[i]
--         local f    = fn .. v
--         local attr = lfs.attributes(f)
--         local readable = posix.access(f,"r")
--
--         -- Three choices:
--
--         -- 1) exact match
--         -- 2) name/default exists
--         -- 3) name/.version exists.
--
--         if (readable and attr and attr.mode == 'file') then
--            result    = f
--            found     = true
--         end
--         dbg.print('(1) fn: ',fn,", found: ",found,", v: ",v,", f: ",f,"\n")
--         if (found and v == '/default') then
--            result    = followDefault(result)
--            dbg.print("(2) result: ",result, " f: ", f, "\n")
--            t.default = 1
--         elseif (found and v == '/.version') then
--            local vf = Master.versionFile(result)
--            if (vf) then
--               local mname = M.new(self,"load",pathJoin(sn,vf))
--               t           = mname:find()
--               t.default   = 1
--               result      = t.fn
--            end
--         end
--         -- One of the three choices matched.
--         if (found) then
--            local _,j = result:find(mpath,1,true)
--            fullName  = result:sub(j+2):gsub("%.lua$","")
--            dbg.print("fullName: ",fullName,"\n")
--            break
--         end
--      end
--      if (found) then break end
--   end
--
--   dbg.print("found:", found, " fn: ",fn,"\n")
--
--   if (not found) then
--      local vv    = pathA[1]
--      local mpath = vv.mpath
--      fn = pathJoin(vv.file, self:version())
--
--      ------------------------------------------------------------
--      -- Search for "last" file in 1st directory since it wasn't
--      -- found with exact or default match.
--      t.default  = 1
--      result = lastFileInDir(fn)
--      if (result) then
--         found = true
--         local _, j = result:find(mpath,1,true)
--         fullName   = result:sub(j+2):gsub("%.lua$","")
--      end
--   end
--
--   ------------------------------------------------------------------
--   -- Build results and return.
--
--   t.fn          = result
--   t.modFullName = fullName
--   t.modName     = sn
--   dbg.print("modName: ",sn," fn: ", result," modFullName: ", fullName,
--             " default: ",t.default,"\n")
--
--   dbg.fini("MName:find")
--   return t
--end

return M


