local pluginName     = select(1,...);
local componentName  = select(2,...);
local signalTable    = select(3,...);
local my_handle      = select(4,...);
----------------------------------------------------------------------------------------------------------------

-- Almost never tested.
-- No support is given.

-- Github: https://github.com/kinglevel
-- Instagram: @kinglevel
-- Please commit or post updates for the community


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

███╗   ███╗███████╗███████╗██╗  ██╗██╗   ██╗ ██████╗  ██████╗  █████╗ ██╗  ██╗
████╗ ████║██╔════╝██╔════╝██║  ██║██║   ██║██╔════╝ ██╔════╝ ██╔══██╗██║  ██║
██╔████╔██║█████╗  ███████╗███████║██║   ██║██║  ███╗██║  ███╗███████║███████║
██║╚██╔╝██║██╔══╝  ╚════██║██╔══██║██║   ██║██║   ██║██║   ██║██╔══██║██╔══██║
██║ ╚═╝ ██║███████╗███████║██║  ██║╚██████╔╝╚██████╔╝╚██████╔╝██║  ██║██║  ██║
╚═╝     ╚═╝╚══════╝╚══════╝╚═╝  ╚═╝ ╚═════╝  ╚═════╝  ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝



README: https://github.com/kinglevel/SnapshotsMA3


]]--






-----------------------------------------------local------------------------------------------------------------

require "gma3_helpers"

local function main()
  --command to run when pressed
  Printf("Snapshots is loaded, check plugin source code for documentation")
end







local function SaveFile(obj)

  local json = require "json"

  local path = GetPathOverrideFor("gma3_library", "")
  local path = path .. "/datapools/plugins/SnapshotsMA3/Snapshots.save"

  local reqpath = GetPathOverrideFor("gma3_library", "")
  local reqpath = reqpath .. "/datapools/plugins/SnapshotsMA3/dkjson.lua"

  local data = json.encode(obj)
  

  -- Write to file
  local file = io.open(path, "w")
  file:write(data)
  file:close()

end





--Store into table
local function Snapshots_DBStore(datapool, page, fader, SnapshotName, MasterLevel)

  --Init a GLOBAL table
  if not Snapshots[SnapshotName] then
    Snapshots[SnapshotName] = {}
  end

  --Prepare Object to store
  local object = {datapool = datapool, page = page, fader=fader, SnapshotName=SnapshotName, MasterLevel=MasterLevel}

  table.insert(Snapshots[SnapshotName], object)
  SaveFile(Snapshots[SnapshotName])
end




------------------------------------------------Global----------------------------------------------------------
--Utillity to clear the table
function Snapshots_Clear(SnapshotName)
  Snapshots[SnapshotName] = {}
  Printf("SnapShots cleared")
end






--Utillity to list the table
function Snapshots_List(SnapshotName)
  gma3_helpers:dump(Snapshots[SnapshotName])
end





--Get the given exec and store the value 
function Snapshots_Store(datapool, page, fader, SnapshotName)

  --Printf("Storing..")

  --Get pool and page
  local x = Root()["ShowData"]
                  ["DataPools"]
                  [tonumber(datapool)]
                  ["Pages"]
                  [tonumber(page)]


  local execs = x:Children()

  -- search over exec table
  for i = 1, #execs do


    -- if exec number is correct
    if execs[i].NO == tonumber(fader) then
      local U = execs[i]

      --Get exec value
      local MasterLevel = Obj.GetFader(U, {
        "Master",
        0
      })

      --Store into table
      Snapshots_DBStore(datapool, page, fader, SnapshotName, MasterLevel)

    end

  end




end




--Set up and run the recall command
function Snapshots_Recall(SnapshotName, fadeTime, overLevel)

  --Init command
  local command = ""

  --for every object in given snapshot
  for i in pairs(Snapshots[SnapshotName]) do

    --Prepare command
    x = "FaderMaster" ..
        " DataPool " .. Snapshots[SnapshotName][i].datapool ..
        " Page " .. Snapshots[SnapshotName][i].page ..
        " Executor " .. Snapshots[SnapshotName][i].fader


    --Override if a level is given
    if overLevel then
      x = x .. " At " .. overLevel
    else
      x = x .. " At " .. Snapshots[SnapshotName][i].MasterLevel
    end


    -- Add fadetime to command if set
    if fadeTime then
      x = x .. "fade " ..fadeTime
    end


    -- Add separation
    y = x .. ";"


    -- Add to one-linder
    command = command .. y

  end


  --Make magic happen like Harry Potter
  Cmd(command)

end








----------------------------------------------------------------------------------------------------------------



--init the snapshot var at plugin load
Snapshots = {}


return main





