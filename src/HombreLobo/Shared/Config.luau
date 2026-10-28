--!strict
-- Valores del ejemplo; no fijan decisiones definitivas del documento maestro.
return {
    Map = {
        Size = 384, CellSize = 12, BaseHeight = 8, HeightAmplitude = 16,
        TreeCount = 70, StatueCount = 5, SiteCount = 8,
        TreeDetail = "Simple", -- Simple: 8 piezas por árbol; Detailed: geometría CC0 original.
    },
    Round = {
        MinimumPlayers = 2, IntermissionSeconds = 12, DurationSeconds = 300,
        DaySeconds = 65, NightTransitionSeconds = 10, ResultsSeconds = 8,
        StudioSoloPractice = false,
        AllowAI = true,
        FixedSeed = 0, -- 0 = una semilla nueva por ronda; otro entero = reproducible.
    },
    Player = { WalkSpeed = 16, WolfSpeed = 27, Health = 100, WolfHealth = 150 },
    AI = { ThinkInterval = 0.25, TargetInterval = 1, PathInterval = 2, MaxWaypoints = 48 },
    Combat = {
        Range = 10, WolfDamage = 35, BladeDamage = 28, Cooldown = 1.1,
        Windup = 0.18, TransformSeconds = 1.5,
        DefendWindow = 0.35, DefendCooldown = 3, DefendDamageMultiplier = 0.2,
        DodgeDistance = 4, DodgeSeconds = 0.18,
        LungeDistance = 18, LungeSeconds = 0.45, LungeCooldown = 8,
        PistolRange = 60, PistolDamage = 12, PistolCooldown = 0.45,
        PistolCapacity = 6, ReloadSeconds = 1.5,
    },
    Audio = {
        SwordDraw = "rbxassetid://9119742466",
        SwordSwing = "rbxassetid://9119699577",
        WolfTransform = "rbxassetid://96994839668376",
        -- Free-to-use Roblox/APM catalog: Henry Parsley, "Favela Funk".
        -- Retimed from its 128 BPM pulse to the reference dance's ~171 BPM.
        VictoryMusic = "rbxassetid://1841682637", VictoryMusicStart = 8.103,
        VictoryBPM = 171, VictoryMusicPlaybackSpeed = 1.3359375,
    },
    Economy = { StartingGold = 80, ChestGold = 20, StatueGold = 30 },
    Abilities = { "Luz", "Escudo", "Carrera", "Fortuna" },
    Ability = { Duration = 8, Cooldown = 24 },
    Shop = {
        Potion = { Name = "Poción de vida", Price = 25 },
        Reroll = { Name = "Nueva habilidad", Price = 40 },
        Boots = { Name = "Botas veloces", Price = 60 },
    },
}
