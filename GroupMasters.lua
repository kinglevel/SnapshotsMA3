local pluginName     = select(1,...);
local componentName  = select(2,...);
local signalTable    = select(3,...);
local my_handle      = select(4,...);
----------------------------------------------------------------------------------------------------------------

-- Almost never tested

-- Github: https://github.com/kinglevel
-- Please commit or post updates for the community.


--[[
                      /mMNh-
                      NM33My
                      -ydds`
                        /.
                        ho
         +yy/          `Md           +yy/
        .N33N`         +MM.         -N33N`
         -+o/          hMMo          o++-
            d:        `MMMm         oy
-:.         yNo`      +MMMM-       yM+        .:-`
d33N:       /MMh.     dMMMMs     -dMM.       :N33d
+ddd:       `MMMm:   .MMMMMN    /NMMd        :hdd+
  ``hh+.     hMMMN+  +MMMMMM: `sMMMMo     -ody `
    -NMNh+.  +MMMMMy`d_SUM_My.hMMMMM-  -odNMm`
     /MMMMNh+:MMMMMMmMMMMMMMNmMMMMMN-odNMMMN-
      oMMMMMMNMMMMMMMMMMMMMMMMMMMMMMNMMMMMM/
       hMMMMMMMMM---LEDvard---MMMMMMMMMMMMo
       `mMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMh
        .NMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMm`
         :mmmmmmmmmmmmmmmmmmmmmmmmmmmmmm-
        `://////////////////////////////.
    -+ymMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMNho/.

"Vision will blind. Severance ties. Median am I. True are all lies"

]]--




local initGroupTable = function()
  local GroupTable = {}
  local GroupCount = 0
  local MADataPools = Root()["ShowData"]["DataPools"]




  for i = 1, Obj.Count(MADataPools) do
    local CurrentDataPool = Obj.Get(MADataPools[i], "name")
    if CurrentDataPool then
      local CurrentGroups = MADataPools[i]["Groups"]
      if not GroupTable[i] then
        GroupTable[i] = {}
        GroupTable[i]["DataPool"] = CurrentDataPool
      end
      for j = 1, 9999 do
        if CurrentGroups[j] and CurrentGroups[j]["Mode"] and CurrentGroups[j]["Mode"] ~= "None" then
          table.insert(GroupTable[i], CurrentGroups[j])
          GroupCount = GroupCount + 1
        end
      end
    end
  end

  return GroupTable, GroupCount
end





local funcGetMasterLevel = function(GroupTable)
  GroupMastersTable = {}
  for key, group in pairs(GroupTable) do
    for k1, faderHandle in pairs(group) do

      if type(k1) == "number" then
        local MasterLevel = Obj.GetFader(faderHandle, {
          "Master",
          0
        })
        table.insert(GroupMastersTable, {faderHandle, MasterLevel})
      end
    end
  end
  return GroupMastersTable
end




local function setGroupMasterValue(faderHandle, faderLevel)
  if type(faderLevel) == "number" then
    if faderLevel > 100 then
      faderLevel = 100
    elseif faderLevel < 0 then
      faderLevel = 0
    end
    Obj.SetFader(faderHandle, {
      ["value"] = faderLevel,
      ["faderDisabled"] = false,
      ["token"] = "Master"
    })
  end
end


-------------------------


local function tableProbe(GroupMastersTable, indent)

    indent = indent or ""  -- default indent is an empty string

    for k, v in pairs(GroupMastersTable) do
        if type(v) == "table" then
            Printf(" ".. indent .. tostring(k) .. ": ".. GroupMastersTable[k][1].name)
            tableProbe(v, indent .. "  ")
        else
            Printf(indent .. tostring(k) .. ": " .. tostring(v))
        end
    end
end


-------------------------


local function debug()

  local GroupTable, GroupCount = initGroupTable()
  local GroupMastersTable = funcGetMasterLevel(GroupTable)

  --Print Table
  tableProbe(GroupMastersTable)

  --examples
  --setGroupMasterValue(GroupMastersTable[1][1], 33)
  --Printf(GroupMastersTable[1][1].name)
  --Printf(GroupMastersTable[1][2])


  --Print all groups and values
  for x in pairs(GroupMastersTable) do
    --Printf(GroupMastersTable[x][1].name)
    --Printf(GroupMastersTable[x][2])
    --SetVar(userVar, pluginName .. varDiv .. "Snap1" .. varDiv .. GroupMastersTable[x][1].name, GroupMastersTable[x][2])
    --Printf(GetVar(userVar, pluginName .. varDiv .. "Snap1" .. varDiv .. GroupMastersTable[x][1].name))
  end



  --SetVar(userVar, pluginName .. ":" .. "Snap1" .. ":" .. GroupMastersTable[x][1].name, GroupMastersTable)
  --Printf(GetVar(userVar, "SnapShots"))
  --Printf(pluginName .. "-" .. "Snap1" .. "-" .. "")

end






local function main()

  Printf("GroupMasters")
  Printf("")

  debug()

end


function GroupMasters(test)
  Printf(test)
end


return main




















