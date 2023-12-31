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

███╗   ███╗███████╗███████╗██╗  ██╗██╗   ██╗ ██████╗  ██████╗  █████╗ ██╗  ██╗
████╗ ████║██╔════╝██╔════╝██║  ██║██║   ██║██╔════╝ ██╔════╝ ██╔══██╗██║  ██║
██╔████╔██║█████╗  ███████╗███████║██║   ██║██║  ███╗██║  ███╗███████║███████║
██║╚██╔╝██║██╔══╝  ╚════██║██╔══██║██║   ██║██║   ██║██║   ██║██╔══██║██╔══██║
██║ ╚═╝ ██║███████╗███████║██║  ██║╚██████╔╝╚██████╔╝╚██████╔╝██║  ██║██║  ██║
╚═╝     ╚═╝╚══════╝╚══════╝╚═╝  ╚═╝ ╚═════╝  ╚═════╝  ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝


----------------------------------------------------------------------------------------------------------------


This plugins enables the user to store and recall fader positions into Snapshots, similar to soundboards.
It can for example be very usefull when running a timecoded show, when the user wants to recall multiple Groupmasters
when the songs goes into different song structures, for example Verse, Chorus, Refrain, Bridge, Solo.

With this plugin, the user can program "almost everything" at 100%, and mix it later live, to be able to adapt the dynamics
for different venues.

* Lighting propagate and bounces, just like sound.
* Haze is sometimes different, due to ventilation and winds.
* Audience needs a kick in their faces to wake up.

This helps the operator to run the shows at ease and be able to adjust for these scenarios, semi-automatic and more accurate.

It works with many diffent kinds of assigned masters on executors.
Fade times only work with some masters, as of 1.9.7.0.



USAGE:

Make sure to CLEAR a snapshot before updating executors into the snapshot.
To store a snapshot, make a macro with multiple lines.
The structure is as follows: Snapshots_Store(datapool, page, executor, SnapshotName)


To store a snapshot:

Lua "Snapshots_Clear('Verse')"
Lua "Snapshots_Store('1','1', '201', 'Verse')"
Lua "Snapshots_Store('1','1', '202', 'Verse')"
Lua "Snapshots_Store('1','1', '203', 'Verse')"
Lua "Snapshots_Store('1','1', '204', 'Verse')"



To recall a snapshot, simply make a macro with:
Lua "Snapshots_Recall('Verse')"


Optional add a fadetime:
Lua "Snapshots_Recall('Verse'. '2')"


Optional recall and override to 100% for a given snapshot on all faders. ("Breakdown button")
Lua "Snapshots_Recall('Verse', '0', '100')"
----------------------------------------------------------------------------------------------------------------
]]--



require "gma3_helpers"




local function main()
  Printf("Snapshots is loaded, check plugin source code for documentation")
  --command to run when pressed
end





--Store stuff
local function Snapshots_DBStore(datapool, page, fader, SnapshotName, MasterLevel)

  --Init a GLOBAL table
  if not Snapshots[SnapshotName] then
    Snapshots[SnapshotName] = {}
  end

  --Prepare Object to store
  local object = {datapool = datapool, page = page, fader=fader, SnapshotName=SnapshotName, MasterLevel=MasterLevel}

  table.insert(Snapshots[SnapshotName], object)
  
end




--GLOBALLY ACCESSED COMMANDS
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

  local x = Root()["ShowData"]
                  ["DataPools"]
                  [tonumber(datapool)]
                  ["Pages"]
                  [tonumber(page)]


  local execs = x:Children()

  -- search over exec table
  for i = 1, #execs do


    -- if fader number is correct
    if execs[i].NO == tonumber(fader) then
      local U = execs[i]

      --Get fader value
      local MasterLevel = Obj.GetFader(U, {
        "Master",
        0
      })


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






return main





