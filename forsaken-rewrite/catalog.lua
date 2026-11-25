-- Original Allen Scripts controls. No external script engine is loaded.
local rows={}
local function add(section,key,label,kind,default,extra)
 local r={Section=section,Key=key,Label=label,Kind=kind,Default=default}
 for k,v in pairs(extra or {}) do r[k]=v end
 rows[#rows+1]=r;return r
end
local function toggle(s,k,l,help)return add(s,k,l,"toggle",false,{Help=help or ""})end
local function number(s,k,l,d,lo,hi,step)return add(s,k,l,"number",d,{Min=lo,Max=hi,Step=step or 1})end
local function choice(s,k,l,d,options)return add(s,k,l,"choice",d,{Options=options})end
local function text(s,k,l,d)return add(s,k,l,"text",d or "")end
local function action(s,k,l)return add(s,k,l,"action")end
for _,role in ipairs({"Survivor","Killer"}) do
 for _,field in ipairs({{"MaxStamina",100,20,500},{"StaminaGain",20,0,100},{"StaminaLoss",10,0,50},{"SprintSpeed",26,10,60}}) do
  toggle("Stamina",role..field[1].."On",role.." custom "..field[1],"Local sprint controller setting; server rules still apply.")
  number("Stamina",role..field[1],field[1].." value",field[2],field[3],field[4],1)
 end
 number("Stamina",role.."SpeedBoost",role.." speed boost (%)",0,0,100,1)
end
toggle("Stamina","NoStaminaPenalty","Remove local recovery delay")
toggle("Stamina","ToggleSprint","Toggle sprint with Left Shift")
toggle("Stamina","ManageSprint","Stop sprinting before exhaustion")
number("Stamina","SprintStopPercent","Stop sprinting below (%)",15,0,75)
action("Stamina","RecommendedStamina","Use recommended stamina settings")
action("Stamina","ResetStamina","Reset custom stamina settings")
for _,entry in ipairs({{"KillerESP","Killers"},{"SurvivorESP","Survivors"},{"ItemESP","Items"},{"ProjectileESP","Projectiles"},{"ObjectESP","Traps and deployables"},{"ObjectiveESP","Map objectives"},{"EventESP","Event pickups"}}) do toggle("Visual",entry[1],entry[2].." ESP") end
add("Visual","ESPTags","Names and distance tags","toggle",true)
add("Visual","ESPHealth","Player health in tags","toggle",true)
number("Visual","ESPTextSize","Tag text size",12,8,24)
number("Visual","ESPFill","Highlight transparency",.8,0,1,.05)
number("Visual","ESPRange","ESP range (studs)",2500,50,5000,50)
text("Visual","KillerColor","Killer color (hex)","FF606F")
text("Visual","SurvivorColor","Survivor color (hex)","64E3A0")
text("Visual","ItemColor","Item color (hex)","7B8CFF")
toggle("Visual","ThreatWarning","Attack warnings","Uses nearby killers' native attack animations.")
toggle("Generators+","SeparatePuzzleTiming","Separate timing for each puzzle")
number("Generators+","ConnectPairDelay","Connect step interval (seconds)",.15,.05,1,.05)
number("Generators+","FlowCellDelay","Flow cell interval (seconds)",.1,.05,1,.05)
number("Generators+","GearTurnDelay","Gear rotation interval (seconds)",.1,.05,1,.05)
number("Generators+","LockPressDelay","Lock press interval (seconds)",.05,.05,1,.05)
number("Generators+","GearTurnDegrees","Clockwise degrees per gear step",90,15,180,15)
toggle("Combat+","AutoM1","Auto primary attack","Uses the equipped actor's native main ability and cooldown guard.")
number("Combat+","AttackRange","Primary attack distance",8,2,20,.5)
number("Combat+","AbilityRange","Character ability distance",14,2,100,1)
number("Combat+","RequestSpacing","Minimum ability request interval",.2,.1,2,.1)
toggle("Combat+","AutoTrapQTE","Auto Azure trap minigame","Presses Space when the native marker enters an unfinished target zone (PC input).")
toggle("Combat+","AutoHookQTE","Auto Nosferatu hook minigame","Reads the active native QTE key; does not submit a fabricated result.")
toggle("Combat+","InfiniteQTEAttempts","Preserve local Azure QTE attempts","Resets the client's failed-attempt counter; server rules remain authoritative.")
number("Combat+","QTEInputInterval","Minimum QTE input interval",.1,.05,.5,.05)
toggle("Combat+","AutoDodge","Move away from incoming attacks")
number("Combat+","DodgeRadius","Attack warning / dodge radius",14,5,35)
toggle("Combat+","AntiBackstab","Face nearby threats behind you")
toggle("Combat+","BodyBlock","Move into a selected opponent's path")
number("Combat+","BodyBlockPrediction","Body-block lead time",.25,0,1,.05)
text("Combat+","AbilityName","Native ability name", "Block")
action("Combat+","UseAbility","Request selected native ability")
number("Combat+","BackstabRadius","Backstab checking distance",8,3,20)
toggle("Combat+","AttackVisualizer","Visualize attack range","Visualization only; does not change server hitboxes.")
number("Combat+","VisualWidth","Visualizer width",5,1,20,.5)
number("Combat+","VisualHeight","Visualizer height",6,1,20,.5)
number("Combat+","VisualLength","Visualizer length",8,1,30,.5)
toggle("Aim","AimBot","Aim assist")
toggle("Aim","SilentAim","Native mouse-position aim","Overrides this game's mouse-position interface; restores on disable.")
choice("Aim","AimMethod","Aim method","Camera",{"Camera","Root","Camera + Root"})
choice("Aim","AimTargetType","Target type","Auto",{"Auto","Killers","Survivors","All"})
choice("Aim","AimPart","Aim part","HumanoidRootPart",{"HumanoidRootPart","Head"})
add("Aim","WallCheck","Wall check","toggle",true)
toggle("Aim","StickyTarget","Keep the same target")
toggle("Aim","LowestHealthTarget","Prefer lowest-health target")
toggle("Aim","AimOnAttack","Aim only during an attack")
add("Aim","AimUseFOV","Use screen FOV","toggle",true)
toggle("Aim","ShowAimFOV","Show FOV circle")
number("Aim","AimFOV","FOV radius (pixels)",150,30,600,10)
number("Aim","AimDistance","Maximum aim distance",300,10,2500,10)
number("Aim","AimPrediction","Prediction (seconds)",.1,0,1,.025)
toggle("Aim","PingPrediction","Add measured ping prediction")
number("Aim","AimSmoothness","Aim smoothing",15,1,40)
number("Aim","AimLockTime","Manual attack lock duration",.6,.1,3,.1)
text("Aim","TargetPlayer","Optional target username")
local abilities={
 {"Survivors","Guest1337","AutoPunch","Automatic punch","Punch"},
 {"Survivors","Guest1337","AutoCharge","Automatic charge","Charge"},
 {"Survivors","Guest1337","GuestAim","Punch / charge aim",false},
 {"Survivors","Shedletsky","AutoSlash","Automatic slash","Slash"},
 {"Survivors","Shedletsky","ShedAim","Slash aim",false},
 {"Survivors","Shedletsky","AutoChicken","Eat chicken when injured","FriedChicken","heal"},
 {"Survivors","Chance","AutoCoinFlip","Automatic coin flip","CoinFlip","utility"},
 {"Survivors","Chance","ChanceAim","Shoot aim",false},
 {"Survivors","Chance","AutoShoot","Automatic shoot","Shoot"},
 {"Survivors","Chance","AutoHatFix","Automatic hat repair","HatFix","utility"},
 {"Survivors","Elliot","PizzaAim","Pizza delivery aim",false,"support"},
 {"Survivors","Elliot","AutoPizza","Throw pizza to injured allies","ThrowPizza","support"},
 {"Survivors","Elliot","AutoRushHour","Rush Hour when threatened","RushHour","threat"},
 {"Survivors","007n7","AutoClone","Clone when threatened","Clone","threat"},
 {"Survivors","Veeronica","AutoSkate","Use Sk8 when available","Sk8","skate"},
 {"Survivors","TwoTime","AutoBackstab","Backstab when behind the killer","Dagger","backstab"},
 {"Survivors","TwoTime","TwoTimeAim","Dagger aim",false},
 {"Survivors","TwoTime","AutoPray","Pray when safe and injured","Pray","safeheal"},
 {"Survivors","Noob","AutoCola","Cola when threatened","BloxyCola","threat"},
 {"Survivors","Noob","AutoGhostburger","Ghostburger when threatened","Ghostburger","threat"},
 {"Survivors","Noob","AutoSlateskin","Slateskin when threatened","SlateskinPotion","threat"},
 {"Survivors","JaneDoe","CrystalAim","Crystal pitch aim",false},
 {"Survivors","JaneDoe","HatchetAim","Hatchet aim",false},
 {"Survivors","Dusekkar","PlasmaAim","Plasma beam aim",false},
 {"Survivors","Dusekkar","AutoProtection","Protect an injured ally","SpawnProtection","support"},
 {"Killers","Noli","NoliAim","Void Rush / Nova aim",false},
 {"Killers","Noli","AutoNova","Use Nova in range","Nova"},
 {"Killers","Noli","AutoVoidRush","Use Void Rush in range","VoidRush"},
 {"Killers","Slasher","SlasherAim","Slasher ability aim",false},
 {"Killers","Slasher","AutoRagingPace","Use Raging Pace","RagingPace","utility"},
 {"Killers","JohnDoe","JohnAim","John Doe projectile aim",false},
 {"Killers","JohnDoe","Auto404","Use 404 Error","404Error","utility"},
 {"Killers","1x1x1x1","OneAim","Mass Infection / Entanglement aim",false},
 {"Killers","Azure","AzureAim","Tentacle ability aim",false},
 {"Killers","Nosferatu","NosferatuAim","Nosferatu ability aim",false},
 {"Killers","c00lkidd","CoolkidAim","Corrupt Nature / dash aim",false},
 {"Killers","Sixer","SixerAim","Demonic Pursuit aim",false},
}
toggle("Survivors","AutoTrick","Veeronica / automatic tricks","Uses the native ready highlight and Space input while skating.")
toggle("Survivors","AutoFarmSk8","Veeronica / skate practice","Starts Sk8 when native requirements permit and steers around your nearest spray zone.")
toggle("Survivors","AntiRebound","Veeronica / disable local phase rebounds")
for _,a in ipairs(abilities) do
 local r=toggle(a[1],a[3],a[2].." / "..a[4],a[5] and "Native ability request; respects the game's cooldown and eligibility guard." or "Predictive aim for this actor.")
 r.Actor=a[2];r.Ability=a[5] or nil;r.AbilityMode=a[6];r.ActorAim=not a[5]
end
local configFields={
 {"Guest1337","ChargingTurnSpeed",2,0,20},{"Guest1337","ChargingSpeed",34,10,80},{"Guest1337","PunchDashForce",40,0,100},
 {"Veeronica","Sk8TurnControl",.65,0,5},{"Veeronica","Sk8Speed",1.15,.1,5},{"Veeronica","Sk8TrickPower",75,0,150},
 {"Veeronica","Sk8BumpPower",12,0,50},{"Veeronica","Sk8TrickStamina",10,0,50},{"Veeronica","Sk8TrickCooldown",1,.1,5},
 {"Veeronica","Sk8StaminaLoss",.85,0,3},{"Veeronica","Sk8StaminaLossOut",1.1,0,3},
 {"Noli","VoidRushDashSpeed",60,10,150},{"Noli","VoidRushTurnSpeed",1,0,10},{"Noli","VoidRushInitialTurnMult",6.6,0,20},
 {"Noli","VoidRushDashLength",3.5,.1,20},{"Noli","VoidRushChargingSpeed",.4,.1,3},
 {"Slasher","EnragedSpeed",20,5,60},{"Slasher","Speed",9,5,40},
 {"Sixer","PursuitHorizontalPenalty",.8,0,2},{"Sixer","PursuitGravity",.6,0,2},{"Sixer","PursuitLength",.8,.1,10},
 {"Sixer","PursuitMaxSpeed",17,5,100},{"Sixer","PursuitBaseSpeed",7,1,60},
 {"Nosferatu","AscentFlight.Speed",6.5,1,40},{"Nosferatu","AscentFlight.Duration",10,1,180},
 {"Nosferatu","AscentBite.Speed",100,20,150},{"Nosferatu","AscentBite.TurnSpeed",4,0,20},
 {"Nosferatu","Spire.TurnControl",10,0,40},{"Nosferatu","Spire.Speed",15,1,60},
 {"JaneDoe","Crystal.MaxChargeTime",2,.1,5},{"JaneDoe","Crystal.MinChargeTime",.25,.1,1},
 {"JaneDoe","Crystal.ChargeSpeedMult",.75,.1,3},{"JaneDoe","Axe.DashSpeed",90,10,150},
 {"Azure","Grab.HookSpeed",270,50,500},{"Azure","GolemFissure.VictimSpeedMult",.3,0,1},
 {"TwoTime","DaggerLungeForce",110,0,150},{"TwoTime","DaggerUncrouchedLungeForce",50,0,150},
}
for _,a in ipairs(configFields) do
 local section=(a[1]=="Guest1337" or a[1]=="Veeronica" or a[1]=="TwoTime" or a[1]=="JaneDoe") and "Survivors" or "Killers"
 local key="Config_"..a[1].."_"..a[2]
 local r=toggle(section,key.."On",a[1].." / override "..a[2],"Local configuration only; this cannot change server-owned damage or duration.")
 r.ConfigActor=a[1];r.ConfigField=a[2];r.ValueKey=key
 number(section,key,a[2].." value",a[3],a[4],a[5],.1)
end
text("Misc","ConfigField","Local actor config field (dot path)","Speed")
number("Misc","ConfigValue","Local config value",12,0,1000,.5)
toggle("Misc","CustomConfig","Apply custom local config field")
for _,name in ipairs({"Slowness","Stunned","Blindness","Confusion","Nausea","Hacked","Glitched","Corrupted","Hallucination","Oblivious","Subspaced","Bleeding"}) do toggle("Antis","Anti_"..name,"Suppress local "..name,"Only client visual/movement effects can be changed; server damage and status remain authoritative.") end
toggle("Antis","AntiInvisible","Reveal locally invisible actor parts")
toggle("Antis","DisableDirectionalSpeed","Disable local directional speed penalty")
toggle("Antis","DisableDirectionalMovement","Use ordinary character movement")
toggle("Antis","NoFootsteps","Mute local footsteps")
toggle("Antis","DisableKillerDoors","Disable local killer door collision")
toggle("Antis","WalkablePuddles","Make local puddles non-collidable")
toggle("Antis","HideFakeGenerators","Hide locally identified fake generators")
toggle("Antis","HideClones","Hide locally identified clone actors")
toggle("Items","AutoPickup","Pick up nearby items and gears")
toggle("Items","PickupReach","Extend local pickup prompt reach","Server pickup-distance checks still apply.")
number("Items","PickupMultiplier","Local prompt distance multiplier",2,1,3,.25)
action("Items","NearestCola","Go to nearest Bloxy Cola")
action("Items","NearestMedkit","Go to nearest Medkit")
action("Items","NearestGear","Go to nearest gear")
toggle("Misc","FullBright","Full bright / no fog")
toggle("Misc","InfiniteZoom","Extended zoom / Invisicam")
toggle("Misc","CustomFOV","Custom field of view")
number("Misc","FOVValue","Field of view",85,40,120)
toggle("Misc","LowEffects","Reduce particles and shadows")
toggle("Misc","EnableJump","Enable local jumping")
number("Misc","JumpPower","Local jump power",50,0,100)
toggle("Misc","AntiAFK","Prevent idle input timeout")
toggle("Misc","EnableChat","Show chat window")
toggle("Misc","HideName","Hide your local nameplate")
toggle("Misc","StatsOverlay","Show local role / health / stamina")
choice("Misc","DeviceOverride","Device override","Default",{"Default","PC","Mobile","Console"})
toggle("Misc","ApplyDeviceOverride","Apply device override")
toggle("Teleport","SpectatePlayer","Spectate selected player")
text("Teleport","TeleportPlayer","Selected player username")
action("Teleport","TeleportPlayerNow","Go to selected player")
action("Teleport","NearestGenerator","Go to nearest incomplete generator")
action("Teleport","ReturnSpawn","Return to saved position")
action("Teleport","SavePosition","Save current position")
action("Teleport","ResetCharacter","Reset character")
action("Teleport","Rejoin","Rejoin current server")
action("Teleport","ServerHop","Find another public server")
text("Animations","AnimationId","Animation asset ID")
number("Animations","AnimationSpeed","Playback speed",1,.1,5,.1)
choice("Animations","AnimationPriority","Priority","Action",{"Idle","Movement","Action","Action2","Action3","Action4"})
action("Animations","PlayAnimation","Play animation")
action("Animations","StopAnimation","Stop your custom animation")
text("Music","MusicId","Audio asset ID")
number("Music","MusicVolume","Volume",.4,0,1,.05)
number("Music","MusicSpeed","Playback speed",1,.25,2,.05)
toggle("Music","MusicLoop","Loop local audio")
action("Music","PlayMusic","Play local audio")
action("Music","StopMusic","Stop local audio")
toggle("Fun","Spin","Spin character locally")
toggle("Fun","Flight","Camera-relative local flight")
number("Fun","FlightSpeed","Flight speed",30,5,100)
toggle("Fun","Noclip","Local character noclip")
number("Fun","SpinSpeed","Spin degrees per second",360,30,1440,30)
action("Fun","Sit","Sit down")
text("UI","BackgroundImage","Background image asset ID")
toggle("UI","ShowBackgroundImage","Show custom background")
number("UI","BackgroundTransparency","Background transparency",.85,0,1,.05)
return rows
