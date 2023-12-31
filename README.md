# GroupMastersMA3

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
The structure is as follows: GroupMasters_Store(datapool, page, executor, SnapshotName)


To store a snapshot:

Lua "GroupMasters_Clear('Verse')"
Lua "GroupMasters_Store('1','1', '201', 'Verse')"
Lua "GroupMasters_Store('1','1', '202', 'Verse')"
Lua "GroupMasters_Store('1','1', '203', 'Verse')"
Lua "GroupMasters_Store('1','1', '204', 'Verse')"



To recall a snapshot, simply make a macro with:
Lua "GroupMasters_Recall('Verse')"


Optional add a fadetime:
Lua "GroupMasters_Recall('Verse'. '2')"


Optional recall and override to 100% for a given snapshot on all faders. ("Breakdown button")
Lua "GroupMasters_Recall('Verse', '0', '100')"