local _, ns = ...
ns.exclude = ns.exclude or {}

-- [ EXCLUSION DATABASE - 2026 CONSOLIDATED ]

-- Expansion 11: The War Within / Midnight
ns.exclude[226258] = { "Delver's Pouch of Reagents", "Does not open" }
ns.exclude[225249] = { "Rattling Bag o'Gold", "Not a container" }
ns.exclude[221375] = { "Pack of Runed Harbinger Crests", "Currency (Manual use)" }
ns.exclude[221373] = { "Satchel of Carved Harbinger Crests", "Currency (Manual use)" }
ns.exclude[221268] = { "Pouch of Weathered Harbinger Crests", "Currency (Manual use)" }
ns.exclude[220776] = { "Gilded Harbinger Crests", "Currency (Manual use)" }
ns.exclude[220773] = { "Runed Harbinger Crests", "Currency (Manual use)" }
ns.exclude[220767] = { "Carved Harbinger Crests", "Currency (Manual use)" }

-- Expansion 10: Dragonflight
ns.exclude[205423] = { "Shadowflame Residue Sack", "Manual use only" }
ns.exclude[204712] = { "Brimming Loamm Niffen Satchel", "Barter Logic (Manual)" }
ns.exclude[202059] = { "Jeweled Dragon's Heart", "Crafting Reagent" }
ns.exclude[202053] = { "Jeweled Dragon's Heart", "Crafting Reagent" }
ns.exclude[192893] = { "Jeweled Dragon's Heart", "Crafting Reagent" }

-- Expansion 09: Shadowlands
ns.exclude[190339] = { "Enlightened Offering", "Rep Token / Manual Use" }
ns.exclude[188787] = { "Locked Broker Luggage", "Requires Key" }
ns.exclude[187351] = { "Stygic Cluster", "Manual Use (BoA Bundle)" }
ns.exclude[186161] = { "Stygian Lockbox", "Requires Key" }
ns.exclude[186160] = { "Locked Artifact Case", "Requires Physical Key (Locked)" }
ns.exclude[185940] = { "Pristine Survival Kit", "Level 60 Boost Lock" }
ns.exclude[184866] = { "Grummlepouch", "Item (Not a bag)" }
ns.exclude[180592] = { "Trapped Stonefiend", "Pet (Not a bag)" }
ns.exclude[180533] = { "Solenium Lockbox", "Requires Physical Key (Locked)" }
ns.exclude[180532] = { "Oxxein Lockbox", "Requires Physical Key (Locked)" }
ns.exclude[180522] = { "Phaedrum Lockbox", "Requires Physical Key (Locked)" }
ns.exclude[180380] = { "Lace Draperies", "Requires Tailoring 100 (Crafting)" }
ns.exclude[180379] = { "Exquisitely Woven Rug", "Requires Tailoring 75 (Crafting)" }
ns.exclude[179311] = { "Oxxein Lockbox", "Requires Physical Key (Locked)" }

-- Expansion 08: Battle for Azeroth
ns.exclude[170502] = { "Waterlogged Toolbox", "User Preference (False)" }
ns.exclude[169475] = { "Barnacled Lockbox", "Locked - Requires Key" }
ns.exclude[168124] = { "Cache of War Resources", "Currency Transfer (Manual)" }

-- Expansion 07: Legion
ns.exclude[157825] = { "Faronis Lockbox", "Does Not Auto Open" }
ns.exclude[157822] = { "Dreamweaver Lockbox", "Does Not Auto Open" }
ns.exclude[152922] = { "Brittle Krokul Chest", "Does Not Auto Open" }
ns.exclude[152108] = { "Legionfall Chest", "Does Not Auto Open" }
ns.exclude[152106] = { "Valarjar Strongbox", "Does Not Auto Open" }
ns.exclude[152103] = { "Dreamweaver Cache", "Does Not Auto Open" }
ns.exclude[143753] = { "Damp Pet Supplies", "Does Not Auto Open" }

-- Expansion 06: Warlords of Draenor
ns.exclude[136926] = { "Nightmare Pod", "Does Not Auto Open" }
ns.exclude[121331] = { "Leystone Lockbox", "Locked - Requires Key" }
ns.exclude[119000] = { "Highmaul Lockbox", "Locked - Requires Key" }
ns.exclude[118697] = { "Big Bag of Pet Supplies", "Does Not Auto Open" }
ns.exclude[118193] = { "Mysterious Shining Lockbox", "Locked - Requires Key" }
ns.exclude[106895] = { "Iron-Bound Junkbox", "Locked (Rogue Pick)" }
-- [ Expansion 05: Mists of Pandaria - Exclusions ]
ns.exclude[ 88567] = { "Ghost Iron Lockbox", "Locked - Requires Key" }
ns.exclude[ 88165] = { "Vine-Cracked Junkbox", "Locked - Requires Rogue Pick" }

-- [ Expansion 04: Cataclysm - Exclusions ]
ns.exclude[ 68729] = { "Elementium Lockbox", "Locked - Requires Key" }
ns.exclude[ 63349] = { "Flame-Scarred Junkbox", "Locked - Requires Rogue Pick" }

-- [ Expansion 03: WotLK - Exclusions ]
ns.exclude[ 46110] = { "Alchemist's Cache", "Profession Locked (Alchemist Only)" }
ns.exclude[ 45986] = { "Tiny Titanium Lockbox", "Locked - Requires Key" }
ns.exclude[ 44700] = { "Brooding Darkwater Clam", "Does Not Open" }
ns.exclude[ 43624] = { "Titanium Lockbox", "Locked - Requires Key" }
ns.exclude[ 43622] = { "Froststeel Lockbox", "Locked - Requires Key" }
ns.exclude[ 43575] = { "Reinforced Junkbox", "Locked - Requires Rogue" }

-- Expansion 02: The Burning Crusade
ns.exclude[191060] = { "Black Sack of Gems", "Drops from Raid Boss" }
ns.exclude[ 34846] = { "Black Sack of Gems", "Drops from Raid Boss" }
ns.exclude[ 31952] = { "Khorium Lockbox", "Requires Key (Locked)" }
ns.exclude[ 29569] = { "Strong Junkbox", "Requires Rogue Pick (Locked)" }
ns.exclude[ 27513] = { "Curious Crate", "Does Not Open" }
ns.exclude[ 27481] = { "Heavy Supply Crate", "Manual use / False positive" }
ns.exclude[ 24476] = { "Jaggal Clam", "Does Not Open" }

-- Legacy / Global
ns.exclude[198657] = { "Forgotten Jewelry Box", "Requires Physical Key (Locked)" }
ns.exclude[194037] = { "Heavy Chest", "Requires Physical Key (Locked)" }

-- Legacy / Classic-era (migrated from fr0z3nUI_AutoOpenXP01.lua)
-- Profession-locked / manual
ns.exclude[ 21743] = { "Large Cluster Rocket Recipes", "Profession Locked (Manual)" }
ns.exclude[ 21742] = { "Large Rocket Recipes", "Profession Locked (Manual)" }
ns.exclude[ 21741] = { "Cluster Rocket Recipes", "Profession Locked (Manual)" }
ns.exclude[ 21740] = { "Small Rocket Recipes", "Profession Locked (Manual)" }

-- Locked containers (requires lockpicking / key)
ns.exclude[191296] = { "Enchanted Lockbox", "Locked - Rogue/Key" }
ns.exclude[190954] = { "Serevite Lockbox", "Locked - Rogue/Key" }
ns.exclude[116920] = { "True Steel Lockbox", "Locked - Rogue/Key" }
ns.exclude[ 19425] = { "Mysterious Lockbox", "Locked - Rogue/Key" }
ns.exclude[ 16885] = { "Heavy Junkbox", "Locked - Rogue/Key" }
ns.exclude[ 16884] = { "Sturdy Junkbox", "Locked - Rogue/Key" }
ns.exclude[ 16883] = { "Worn Junkbox", "Locked - Rogue/Key" }
ns.exclude[ 16882] = { "Battered Junkbox", "Locked - Rogue/Key" }
ns.exclude[ 13918] = { "Reinforced Locked Chest", "Locked - Rogue/Key" }
ns.exclude[ 13875] = { "Ironbound Locked Chest", "Locked - Rogue/Key" }
ns.exclude[ 12033] = { "Thaurissan Family Jewels", "Locked - Rogue/Key" }
ns.exclude[  7870] = { "Thaumaturgy Vessel Lockbox", "Locked - Rogue/Key" }
ns.exclude[  7209] = { "Tazan's Satchel", "Locked - Rogue/Key" }
ns.exclude[  6355] = { "Sturdy Locked Chest", "Locked - Rogue/Key" }
ns.exclude[  6354] = { "Small Locked Chest", "Locked - Rogue/Key" }
ns.exclude[  5760] = { "Eternium Lockbox", "Locked - Rogue/Key" }
ns.exclude[  5759] = { "Thorium Lockbox", "Locked - Rogue/Key" }
ns.exclude[  5758] = { "Mithril Lockbox", "Locked - Rogue/Key" }
ns.exclude[  4638] = { "Reinforced Steel Lockbox", "Locked - Rogue/Key" }
ns.exclude[  4637] = { "Steel Lockbox", "Locked - Rogue/Key" }
ns.exclude[  4636] = { "Strong Iron Lockbox", "Locked - Rogue/Key" }
ns.exclude[  4634] = { "Iron Lockbox", "Locked - Rogue/Key" }
ns.exclude[  4633] = { "Heavy Bronze Lockbox", "Locked - Rogue/Key" }
ns.exclude[  4632] = { "Ornate Bronze Lockbox", "Locked - Rogue/Key" }

-- Items that don't open / problematic
ns.exclude[198395] = { "Dull Spined Clam", "Clams Cannot AutoOpen" }
ns.exclude[ 36781] = { "Darkwater Clam", "Clams Cannot AutoOpen" }
ns.exclude[ 15874] = { "Soft-shelled Clam", "Clams Cannot AutoOpen" }
ns.exclude[  7973] = { "Big-Mouth Clams", "Clams Cannot AutoOpen" }
ns.exclude[  5524] = { "Thick-shelled Clam", "Clams Cannot AutoOpen" }
ns.exclude[  5523] = { "Small Barnacled Clam", "Clams Cannot AutoOpen" }