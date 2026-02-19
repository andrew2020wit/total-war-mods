-- AF Armageddon, "Total War Warhammer 3" modification

local mod_version = '4.0.1'

local settings = {
    enable_logging = false,
    regions_percent = 4,
    time_percent = 2,
    log_file_name = '!!af_armageddon.txt',
    experience_for_character = 100,
    add_chevron_each_turn = 2, -- each second turn
    skip_culture = {
        wh3_main_ksl_kislev = false,
        wh3_main_dae_daemons = false,
        wh3_main_kho_khorne = false,
        wh3_main_nur_nurgle = false,
        wh3_main_sla_slaanesh = false,
        wh3_main_tze_tzeentch = false,
        wh3_main_ogr_ogre_kingdoms = false,
        wh3_dlc23_chd_chaos_dwarfs = false,
        wh3_main_cth_cathay = false,
        wh2_main_hef_high_elves = false,
        wh2_main_lzd_lizardmen = false,
        wh2_main_def_dark_elves = false,
        wh2_main_skv_skaven = false,
        wh2_dlc09_tmb_tomb_kings = false,
        wh2_dlc11_cst_vampire_coast = false,
        wh_main_emp_empire = false,
        wh_main_dwf_dwarfs = false,
        wh_main_grn_greenskins = false,
        wh_main_vmp_vampire_counts = false,
        wh_main_chs_chaos = false,
        wh_dlc03_bst_beastmen = false,
        wh_dlc05_wef_wood_elves = false,
        wh_main_brt_bretonnia = false,
        wh_dlc08_nor_norsca = false,
        wh2_main_rogue = false,
        rebels = true,
    },
    skip_faction = {
        wh3_main_ksl_the_ice_court = false,
        wh3_main_dae_daemon_prince = false,
        wh3_main_kho_exiles_of_khorne = false,
        wh3_dlc26_kho_skulltaker = false,
        wh3_dlc26_kho_arbaal = false,
        wh3_main_nur_poxmakers_of_nurgle = false,
        wh3_dlc25_nur_tamurkhan = false,
        wh3_dlc25_nur_epidemius = false,
        wh3_main_sla_seducers_of_slaanesh = false,
        wh3_dlc27_sla_the_tormentors = false,
        wh3_main_tze_oracles_of_tzeentch = false,
        wh3_dlc24_tze_the_deceivers = false,
        wh3_main_ksl_the_great_orthodoxy = false,
        wh3_main_ksl_ursun_revivalists = false,
        wh3_dlc24_ksl_daughters_of_the_forest = false,
        wh3_main_ogr_goldtooth = false,
        wh3_main_ogr_disciples_of_the_maw = false,
        wh3_dlc26_ogr_golgfag = false,
        wh3_dlc23_chd_astragoth = false,
        wh3_dlc23_chd_legion_of_azgorh = false,
        wh3_dlc23_chd_zhatan = false,
        wh3_main_cth_the_northern_provinces = false,
        wh3_main_cth_the_western_provinces = false,
        wh3_dlc24_cth_the_celestial_court = false,
        wh2_main_hef_eataine = false,
        wh2_main_hef_order_of_loremasters = false,
        wh2_main_hef_avelorn = false,
        wh2_main_hef_nagarythe = false,
        wh2_main_hef_yvresse = false,
        wh2_dlc15_hef_imrik = false,
        wh3_dlc27_hef_aislinn = false,
        wh2_dlc17_lzd_oxyotl = false,
        wh2_main_lzd_hexoatl = false,
        wh2_main_lzd_last_defenders = false,
        wh2_dlc12_lzd_cult_of_sotek = false,
        wh2_main_lzd_tlaqua = false,
        wh2_dlc13_lzd_spirits_of_the_jungle = false,
        wh2_main_lzd_itza = false,
        wh2_main_def_naggarond = false,
        wh2_main_def_cult_of_pleasure = false,
        wh2_main_def_har_ganeth = false,
        wh2_dlc11_def_the_blessed_dread = false,
        wh2_main_def_hag_graef = false,
        wh2_twa03_def_rakarth = false,
        wh2_main_skv_clan_mors = false,
        wh2_main_skv_clan_pestilens = false,
        wh2_dlc09_skv_clan_rictus = false,
        wh2_main_skv_clan_skryre = false,
        wh2_main_skv_clan_moulder = false,
        wh2_main_skv_clan_eshin = false,
        wh2_dlc09_tmb_khemri = false,
        wh2_dlc09_tmb_lybaras = false,
        wh2_dlc09_tmb_exiles_of_nehek = false,
        wh2_dlc09_tmb_followers_of_nagash = false,
        wh2_dlc11_cst_vampire_coast = false,
        wh2_dlc11_cst_noctilus = false,
        wh2_dlc11_cst_the_drowned = false,
        wh2_dlc11_cst_pirates_of_sartosa = false,
        wh_main_emp_empire = false,
        wh2_dlc13_emp_golden_order = false,
        wh3_main_emp_cult_of_sigmar = false,
        wh2_dlc13_emp_the_huntmarshals_expedition = false,
        wh_main_emp_wissenland = false,
        wh_main_dwf_dwarfs = false,
        wh_main_dwf_karak_kadrin = false,
        wh_main_dwf_karak_izor = false,
        wh3_main_dwf_the_ancestral_throng = false,
        wh2_dlc17_dwf_thorek_ironbrow = false,
        wh3_dlc25_dwf_malakai = false,
        wh_main_grn_greenskins = false,
        wh_main_grn_crooked_moon = false,
        wh2_dlc15_grn_bonerattlaz = false,
        wh_main_grn_orcs_of_the_bloody_hand = false,
        wh2_dlc15_grn_broken_axe = false,
        wh3_dlc26_grn_gorbad_ironclaw = false,
        wh_main_vmp_vampire_counts = false,
        wh2_dlc11_vmp_the_barrow_legion = false,
        wh3_main_vmp_caravan_of_blue_roses = false,
        wh_main_vmp_schwartzhafen = false,
        wh_main_chs_chaos = false,
        wh3_dlc20_chs_kholek = false,
        wh3_dlc20_chs_sigvald = false,
        wh3_dlc20_chs_azazel = false,
        wh3_dlc20_chs_festus = false,
        wh3_dlc20_chs_valkia = false,
        wh3_dlc20_chs_vilitch = false,
        wh3_main_chs_shadow_legion = false,
        wh_dlc03_bst_beastmen = false,
        wh2_dlc17_bst_malagor = false,
        wh_dlc05_bst_morghur_herd = false,
        wh2_dlc17_bst_taurox = false,
        wh_dlc05_wef_wood_elves = false,
        wh_dlc05_wef_argwylon = false,
        wh2_dlc16_wef_sisters_of_twilight = false,
        wh2_dlc16_wef_drycha = false,
        wh_main_brt_bretonnia = false,
        wh_main_brt_carcassonne = false,
        wh_main_brt_bordeleaux = false,
        wh2_dlc14_brt_chevaliers_de_lyonesse = false,
        wh_dlc08_nor_norsca = false,
        wh_dlc08_nor_wintertooth = false,
        wh3_dlc27_nor_sayl = false,
        wh3_main_kho_bloody_sword = false,
        wh3_main_kho_brazen_throne = false,
        wh3_main_kho_crimson_skull = false,
        wh3_main_nur_bubonic_swarm = false,
        wh3_main_nur_maggoth_kin = false,
        wh3_dlc20_nur_pallid_nurslings = false,
        wh3_main_sla_rapturous_excess = false,
        wh3_main_sla_subtle_torture = false,
        wh3_dlc20_sla_keepers_of_bliss = false,
        wh3_main_tze_all_seeing_eye = false,
        wh3_main_tze_broken_wheel = false,
        wh3_main_tze_flaming_scribes = false,
        wh3_main_ksl_ropsmenn_clan = false,
        wh3_dlc20_tze_apostles_of_change = false,
        wh3_main_tze_sarthoraels_watchers = false,
        wh3_dlc27_sla_masque_of_slaanesh = false,
        wh3_main_ksl_druzhina_enclave = false,
        wh3_main_ogr_blood_guzzlers = false,
        wh3_main_ogr_crossed_clubs = false,
        wh3_main_ogre_sharktooth = false,
        wh3_main_ogr_feastmaster = false,
        wh3_main_ogre_the_famished = false,
        wh3_main_ogre_flamegullets = false,
        wh3_main_ogre_stoneshatter = false,
        wh3_main_ogr_fleshgreeders = false,
        wh3_main_ogr_fulg = false,
        wh3_main_ogr_lazarghs = false,
        wh3_main_ogr_mountaineaters = false,
        wh3_main_ogr_rock_skulls = false,
        wh3_main_ogr_sabreskin = false,
        wh3_main_ogr_sons_of_the_mountain = false,
        wh3_main_ogr_thunderguts = false,
        wh3_main_ogr_treehammers = false,
        wh3_main_cth_burning_wind_nomads = false,
        wh3_main_cth_celestial_loyalists = false,
        wh3_main_cth_dissenter_lords_of_jinshen = false,
        wh3_main_cth_eastern_river_lords = false,
        wh3_main_cth_imperial_wardens = false,
        wh3_main_cth_rebel_lords_of_nan_yang = false,
        wh3_main_cth_the_jade_custodians = false,
        wh2_main_hef_caledor = false,
        wh2_main_hef_citadel_of_dusk = false,
        wh2_main_hef_cothique = false,
        wh2_main_hef_ellyrion = false,
        wh2_main_hef_saphery = false,
        wh2_main_hef_tiranoc = false,
        wh2_dlc13_lzd_defenders_of_the_great_plan = false,
        wh2_main_lzd_sentinels_of_xeti = false,
        wh2_main_lzd_southern_sentinels = false,
        wh3_main_lzd_tepoks_spawn = false,
        wh2_main_lzd_tlaxtlan = false,
        wh2_dlc16_lzd_wardens_of_the_living_pools = false,
        wh2_main_lzd_xlanhuapec = false,
        wh2_main_lzd_zlatan = false,
        wh2_main_def_bleak_holds = false,
        wh2_main_def_blood_hall_coven = false,
        wh2_main_def_clar_karond = false,
        wh2_main_def_cult_of_excess = false,
        wh2_main_def_deadwood_sentinels = false,
        wh2_main_def_ghrond = false,
        wh2_main_def_karond_kar = false,
        wh2_main_def_scourge_of_khaine = false,
        wh2_main_def_ssildra_tor = false,
        wh2_main_def_drackla_coven = false,
        wh3_main_skv_clan_carrion = false,
        wh2_dlc15_skv_clan_ferrik = false,
        wh2_dlc16_skv_clan_gritus = false,
        wh2_dlc15_skv_clan_kreepus = false,
        wh3_main_skv_clan_krizzor = false,
        wh2_dlc12_skv_clan_mange = false,
        wh3_main_skv_clan_morbidus = false,
        wh2_main_skv_clan_mordkin = false,
        wh2_main_skv_clan_septik = false,
        wh2_main_skv_clan_spittel = false,
        wh3_main_skv_clan_verms = false,
        wh3_main_skv_clan_treecherik = false,
        wh3_main_tmb_deserters_of_khatep = false,
        wh2_dlc09_tmb_dune_kingdoms = false,
        wh2_dlc09_tmb_numas = false,
        wh2_dlc09_tmb_rakaph_dynasty = false,
        wh2_dlc09_tmb_the_sentinels = false,
        wh3_dlc21_cst_dead_flag_fleet = false,
        wh_main_emp_averland = false,
        wh_main_emp_hochland = false,
        wh_main_emp_marienburg = false,
        wh_main_emp_middenland = false,
        wh2_main_emp_new_world_colonies = false,
        wh_main_emp_nordland = false,
        wh_main_emp_ostermark = false,
        wh_main_emp_ostland = false,
        wh_main_emp_stirland = false,
        wh_main_emp_talabecland = false,
        wh_main_dwf_barak_varr = false,
        wh2_dlc15_dwf_clan_helhein = false,
        wh2_main_dwf_greybeards_prospectors = false,
        wh3_main_dwf_karak_azorn = false,
        wh_main_dwf_karak_azul = false,
        wh_main_dwf_karak_hirn = false,
        wh_main_dwf_karak_norn = false,
        wh_main_dwf_karak_ziflin = false,
        wh2_main_dwf_spine_of_sotek_dwarfs = false,
        wh_main_dwf_zhufbar = false,
        wh2_main_grn_arachnos = false,
        wh_main_grn_black_venom = false,
        wh_main_grn_bloody_spearz = false,
        wh2_main_grn_blue_vipers = false,
        wh2_dlc16_grn_naggaroth_orcs = false,
        wh_main_grn_broken_nose = false,
        wh3_dlc26_grn_cluster_eye_tribe = false,
        wh2_dlc16_grn_creeping_death = false,
        wh_main_grn_necksnappers = false,
        wh3_main_grn_da_cage_breakaz = false,
        wh3_main_grn_dark_land_orcs = false,
        wh3_main_grn_dimned_sun = false,
        wh3_main_grn_drippin_fangs = false,
        wh2_dlc12_grn_leaf_cutterz_tribe = false,
        wh3_main_grn_moon_howlerz = false,
        wh_main_grn_red_eye = false,
        wh_main_grn_red_fangs = false,
        wh_main_grn_scabby_eye = false,
        ["wh_main_grn_skull-takerz"] = false,
        wh2_dlc15_grn_skull_crag = false,
        wh_main_grn_skullsmasherz = false,
        wh3_main_grn_slaves_of_zharr = false,
        wh_main_grn_teef_snatchaz = false,
        wh_dlc03_grn_black_pit = false,
        wh_main_grn_top_knotz = false,
        wh3_main_grn_tusked_sunz = false,
        wh3_dlc21_vmp_jiangshi_rebels = false,
        wh3_main_vmp_lahmian_sisterhood = false,
        wh_main_vmp_mousillon = false,
        wh2_main_vmp_necrarch_brotherhood = false,
        wh3_main_ie_vmp_sires_of_mourkain = false,
        wh2_main_vmp_strygos_empire = false,
        wh_main_vmp_rival_sylvanian_vamps = false,
        wh2_main_vmp_the_silver_host = false,
        wh3_dlc25_vmp_the_court_of_night = false,
        wh3_main_chs_khazag = false,
        wh_main_teb_border_princes = false,
        wh_main_teb_estalia = false,
        wh_main_teb_tilea = false,
        wh_dlc03_bst_jagged_horn = false,
        wh2_main_bst_manblight = false,
        wh_dlc03_bst_redhorn = false,
        wh2_main_bst_ripper_horn = false,
        wh2_main_bst_shadowgor = false,
        wh2_main_wef_bowmen_of_oreon = false,
        wh3_main_wef_laurelorn = false,
        wh3_dlc21_wef_spirits_of_shanlin = false,
        wh_dlc05_wef_torgovann = false,
        wh_dlc05_wef_wydrioth = false,
        wh_main_brt_artois = false,
        wh_main_brt_bastonne = false,
        wh3_main_brt_aquitaine = false,
        wh2_main_brt_knights_of_origo = false,
        wh_main_brt_lyonesse = false,
        wh_main_brt_parravon = false,
        wh2_main_brt_thegans_crusaders = false,
        wh3_dlc23_chd_minor_faction = false,
        wh2_main_nor_aghol = false,
        wh3_dlc23_chd_conclave = false,
        wh_main_nor_baersonling = false,
        wh3_dlc27_the_narj = false,
        wh_dlc08_nor_goromadny_tribe = false,
        wh3_dlc20_nor_kul = false,
        wh2_main_nor_mung = false,
        wh_dlc08_nor_naglfarlings = false,
        wh_main_nor_sarl = false,
        wh_main_nor_skaeling = false,
        wh2_main_nor_skeggi = false,
        wh_dlc08_nor_vanaheimlings = false,
        wh_main_nor_varg = false,
        wh3_dlc21_nor_wyrmkins = false,
        wh3_dlc20_nor_yusak = false,
        wh3_dlc27_nor_avags = false,
        wh2_dlc11_cst_rogue_bleak_coast_buccaneers = false,
        wh2_dlc11_cst_rogue_boyz_of_the_forbidden_coast = false,
        wh2_dlc11_cst_rogue_freebooters_of_port_royale = false,
        wh2_dlc11_cst_rogue_grey_point_scuttlers = false,
        wh2_dlc11_cst_rogue_terrors_of_the_dark_straights = false,
        wh2_dlc11_cst_rogue_the_churning_gulf_raiders = false,
        wh2_dlc11_cst_rogue_tyrants_of_the_black_ocean = false,
        wh3_dlc27_hef_aislinn_confederation_owner = false,
        rebels = false,
    },
}

local function log(text)
    if not settings.enable_logging then
        return
    end

    local file = io.open(settings.log_file_name, "a")

    if not file then return end

    file:write(tostring(text) .. "\n")
    file:close()
end

log('Armageddon start! ' .. os.date() .. ' v. ' .. mod_version)

local function add_xp_to_army(faction_name)
    local faction =  cm:get_faction(faction_name)  
    local force_list = faction:military_force_list()

    log('add_xp_to_army, faction: '.. faction_name)

    for i = 0, force_list:num_items() - 1 do
        local force = force_list:item_at(i)

        if force:has_general() then
            local unit_list = force:unit_list()            

            for j = 0, unit_list:num_items() - 1 do
                local unit = unit_list:item_at(j)

                if not unit:is_null_interface() then
                    local rank = unit:experience_level()                  

                    if rank < 9 then
                        cm:add_experience_to_unit(unit, 1)
                    end

                    local new_rank = unit:experience_level()

                    log(
                    'unit ' .. unit:unit_key()
                    .. ' rank: ' .. tostring(rank) .. ' => ' .. tostring(new_rank)
                    )                    
                end
            end
        end
    end
end

local function add_xp_to_characters(faction_name)
        local faction =  cm:get_faction(faction_name)    
        local xp_bonus = cm:turn_number() * settings.experience_for_character

        local characters = faction:character_list()

        for i = 0, characters:num_items() - 1 do
            local character = characters:item_at(i)

            local character_str = cm:char_lookup_str(character)

            local level_before = character:rank()

            cm:add_agent_experience(character_str, xp_bonus)

            local level_after = character:rank()

            local name = character:character_subtype_key()

            log('add xp to character ' .. name .. ' : ' .. tostring(xp_bonus) 
                .. ' level: ' .. tostring(level_before) .. ' => ' .. tostring(level_after)
            )
        end
end

local function help_ai_each_turn(context)
    local current_faction = context:faction()
    local current_faction_name = current_faction:name()
    local current_turn = cm:turn_number()

    if (current_faction:is_rebel()) then
        log('skip rebel')
        return
    end

    if current_faction:is_human() then
        log('settings, current_turn:' .. current_turn ..
         ', regions_gold_bonus_percent: ' .. settings.regions_percent ..
         ', time_gold_bonus_percent: ' .. settings.time_percent
         ', add_chevron_each_turn: ' .. settings.add_chevron_each_turn
         .. ', character exp: ' .. settings.experience_for_character
        )

        return
    end

    local player_faction_name = cm:get_local_faction_name(true)
    local player_faction = cm:get_faction(player_faction_name)

    local current_culture = current_faction:culture()
    local player_culture = player_faction:culture()

    log('faction: ' .. current_faction_name .. ', culture: ' .. current_culture)

    if (current_culture == player_culture) then
        log('the same culture, skip')
        return
    end

    if (settings.skip_culture[current_culture]) then
        log('skip culture (settings): ' .. current_culture)
        return
    end

    if (settings.skip_faction[current_faction_name]) then
        log('skip faction (settings): ' .. current_faction_name)
        return
    end

    local player_regions_number = player_faction:region_list():num_items()

    local time_multiplier = settings.time_percent * current_turn / 100
    local region_multiplier = settings.regions_percent * player_regions_number / 100

    local ai_income = current_faction:income()

    local gold_bonus = (region_multiplier + time_multiplier) * ai_income;

    local debug_treasury_before = current_faction:treasury()

    -- Add money
    cm:treasury_mod(current_faction_name, gold_bonus)

    local debug_treasury_after = current_faction:treasury()

    log('=========== gold_bonus ===============\n'..
        'Faction: ' .. current_faction_name ..  '\n' ..
        "$$$$ ai_income: " .. tostring(ai_income) .. '\n' ..
        "++++ gold_bonus: " .. tostring(gold_bonus) .. '\n' ..
        ". time_multiplier: " .. tostring(time_multiplier) .. '\n' ..
        ". player_regions_number: " .. tostring(player_regions_number) .. '\n' ..
        ". region_multiplier: " .. tostring(region_multiplier) .. '\n' ..        
        ". treasury_before - after: " .. tostring(debug_treasury_before) .. ' => ' .. debug_treasury_after .. '\n' ..        
        "===================="
    )

    add_xp_to_characters(current_faction_name)

    if current_turn % settings.add_chevron_each_turn == 0 then
        add_xp_to_army(current_faction_name)

    else
        log('skip add_xp_to_army for this turn')        
    end
    

end

core:add_listener(
    "AddMoneyToAI",
    "FactionTurnStart",
    true,
    help_ai_each_turn,
    true
)
