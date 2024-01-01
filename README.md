# Snapshots

This plugins enables the user to store and recall fader positions into Snapshots for GrandMA3, similar to soundboards.
It can for example be very usefull when running a timecoded show, when the user wants to recall multiple Groupmasters
or other executors into different positions.

When a songs goes into different song structures, for example Verse, Chorus, Refrain, Bridge, Solo, this can be especially useful.

With this plugin, the user can program "almost everything" at 100%, and mix it later, "live".

* Lighting propagate and bounces in the rooms, just like sound.
* Haze is sometimes different, due to ventilation, wind or other air pressure related issues.
* Audience needs a kick in their faces to wake up.


This helps the operator to run the shows at ease and be able to adjust for these scenarios, semi-automatic, and more accurate.


### KNOWN ISSUES:

* It works with many diffent kinds of assigned masters on executors. Some may not work.
* Fade times only work with some masters, as of 1.9.7.0.
* Values stored into snapshots may not live between showfile loads or console reboots.
* Not tested in a network scenario, yet.
* Loads lua code globally, probably a better way to do it.


### USAGE:

Make sure to CLEAR a snapshot before updating executors into the snapshot.
To store a snapshot, make a macro with multiple lines.
The structure is as follows: Snapshots_Store(datapool, page, executor, SnapshotName)




#### To store a snapshot:
```
Lua "Snapshots_Clear('Verse')"
Lua "Snapshots_Store('1','1', '201', 'Verse')"
Lua "Snapshots_Store('1','1', '202', 'Verse')"
Lua "Snapshots_Store('1','1', '203', 'Verse')"
Lua "Snapshots_Store('1','1', '204', 'Verse')"
```


#### To recall a snapshot, simply make a macro with:
```
Lua "Snapshots_Recall('Verse')"
```

#### Optional add a fadetime:
```
Lua "Snapshots_Recall('Verse'. '2')"
```


#### Optional recall and override to 100% for a given snapshot on all faders. ("Breakdown button")
```
Lua "Snapshots_Recall('Verse', '0', '100')"
```



### INSTALLATION:

Download the lua files, or clone this rep as a haxx0r.

#### MacOS:
```
cd ~/MALightingTechnology/gma3_library/datapools/plugins/
git clone git@github.com:kinglevel/SnapshotsMA3.git
```

#### Windows:
```
cd %ProgramData%/MALightingTechnology/gma3_library/datapools/plugins/
git clone git@github.com:kinglevel/SnapshotsMA3.git
```

### HOW TO RUN IT:

Just import the plugin in your show file, make the macros, and you should be all set.