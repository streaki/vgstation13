
/obj/machinery/power/tool_charger
	name = "tool charger"
	desc = "A charger for certain engineering tools. Draws power directly from the grid."
	icon = 'icons/obj/machines/tool_charger.dmi'
	icon_state = "tool_charger"
	anchored = 1
	use_power = 1
	density = 1
	idle_power_usage = 10
	active_power_usage = 10 //Power is already drained to charge batteries
	var/obj/item/device/rcd/charging = null
	var/transfer_percentage = 0.2 //Percentage of surplus power that we can use
	var/transfer_efficiency = 0.7 //How much power ends up in the battery in percentage ?
	var/transfer_rate_coeff = 1 //What is the quality of the parts that transfer energy (capacitators) ?
	var/transfer_efficiency_bonus = 0 //What is the efficiency "bonus" (additive to percentage) from the parts used (scanning module) ?
	var/chargelevel = -1 //Controls what's shown on the charge gauge
	var/has_beeped = FALSE
	var/turned_on = 0
	var/energy_charged = 0
	var/max_charge = TEN_MEGAWATTS
	machine_flags = SCREWTOGGLE | WRENCHMOVE | FIXED2WORK | CROWDESTROY | EJECTNOTDEL //| EMAGGABLE
	ghost_read = 0 // Deactivate ghost touching.
	ghost_write = 0

/obj/machinery/power/tool_charger/Destroy()
	qdel(charging)
	charging = null
	..()

/obj/machinery/power/tool_charger/update_icon()
	if(charging && turned_on)
		icon_state = "tool_charger_on"
		return
	if(charging)
		icon_state = "tool_charger_ready"
		return
	icon_state = "tool_charger"
	return

/obj/machinery/power/tool_charger/proc/update_overlays()
	overlays.len = 0
	if(panel_open)
		overlays += image(icon = icon, icon_state = "tc_hatch")
	if(chargelevel >= 0)
		overlays += image(icon = icon, icon_state = "tc_c[chargelevel]")

/obj/machinery/power/tool_charger/emp_act(var/severity)
	..()    // check if this does anything. Possibly add an explosion or electrocution or something

/obj/machinery/power/tool_charger/New()
	. = ..()
	component_parts = newlist(
		/obj/item/weapon/circuitboard/tool_charger,
		/obj/item/weapon/stock_parts/scanning_module,
		/obj/item/weapon/stock_parts/capacitor,
		/obj/item/weapon/stock_parts/capacitor,
		/obj/item/weapon/stock_parts/console_screen
	) // Fashioned from the cell charger, they both serve a similar purpose
	RefreshParts()
	if(anchored)
		connect_to_network()

/obj/machinery/power/tool_charger/togglePanelOpen(var/obj/item/toggleitem, var/mob/user)
	if(charging && turned_on)
		to_chat(user, "<span class='warning'>You can't open the maintenance panel while \the [src] is working.</span>")
		return 1
	return ..()

/obj/machinery/power/tool_charger/attackby(obj/item/T, mob/user)
	if(issilicon(user))
		if(!isMoMMI(user))  // maybe add borg support maybe
			return 1
	. = ..()
	if(.)
		update_overlays()	// maybe the panel is open
		if(T.is_wrench(user))	// connect or disconnect from the network upon (un)wrenching
			if(anchored)
				connect_to_network()
			else
				disconnect_from_network()
				turn_off()
		return 1
	if(stat & BROKEN)
		to_chat(user, "<span class='notice'>[src] is broken.</span>")
		return
	if(charging)
		if(isgripper(T) && isrobot(user))
			attack_hand(user)
			return 1
		to_chat(user, "<span class='warning'>There's \a [charging] already charging inside!</span>")
		return 1
	if(!anchored)
		to_chat(user, "<span class='warning'>You must secure \the [src] before you can make use of it!</span>")
		return 1
	if(istype(T, /obj/item/device/rcd/rpd))
		if(!user.drop_item(T, src))
			user << "<span class='warning'>You can't let go of \the [T]!</span>"
			return 1
		charging = T
		has_beeped = FALSE
		use_power = 2
		update_icon()
		return 1

/obj/machinery/power/tool_charger/attack_hand(mob/user as mob)
	if(user.incapacitated())
		return
	if(charging)
		if(turned_on)
			turn_off()
		eject_tool()

/obj/machinery/power/tool_charger/AltClick(mob/user)
	if(!user.incapacitated() && Adjacent(user) && user.dexterity_check())
		toggle_on()
		return
	return ..()

/obj/machinery/power/tool_charger/verb/toggle_on()
	set name = "Toggle on"
	set category = "Object"
	set src in oview(1)
	if(usr.incapacitated()) //the magic of verbs
		return
	if(!anchored || !powernet)
		to_chat(usr, "<span class='warning'>\The [src] has to be wrenched over a wire knot to work.</span>")
		return
	if(!charging)
		to_chat(usr, "<span class='warning'>There's no item inside.</span>")
		return
	if(panel_open)
		to_chat(usr, "<span class='warning'>You can't start \the [src] while the maintenance panel is open.</span>")
		return
	if(turned_on)
		turn_off()
	else
		turn_on()

/obj/machinery/power/tool_charger/proc/eject_tool()
	charging.forceMove(loc)
	charging = null
	use_power = 1
	update_icon()

/obj/machinery/power/tool_charger/process()
	if(!anchored)
		update_icon()
		return
	if(stat & BROKEN)
		if(charging)
			eject_tool()
		return
	if(charging && turned_on)
		if(energy_charged >= max_charge)
			if(istype(charging, /obj/item/device/rcd/rpd))
				new /obj/item/device/rcd/rpd/turbo().forceMove(loc)
			qdel(charging)
			charging = null
			turn_off()
			energy_charged = 0
			playsound(src, 'sound/machines/ding.ogg', 50, 1)
			return
		var/energy_consumed = surplus() * transfer_percentage
		if(energy_consumed > (800000 * 0.2)) // surplus energy must be higher than 800000 W (if stock parts are used) - only achievable if hotwired to engines
			add_load(energy_consumed)
			energy_charged += (energy_consumed * transfer_efficiency)
			if(prob(20))
				spark(src, 5)
			update_chargelevel()
			return
		else
			turn_off()
			visible_message("<span class='notice'>[src] shuts down due to insufficient power.</span>")
			return
	else if(energy_charged > 0)
		energy_charged -= 100000 // don't just delete the energy after the item was removed; lose it over time, however
		update_chargelevel()
	else
		energy_charged = 0
		update_icon()
		chargelevel = -1
		update_overlays()
		processing_objects.Remove(src)

/obj/machinery/power/tool_charger/proc/update_chargelevel()
	var/newlevel = round(energy_charged / max_charge * 5)
	if(newlevel != chargelevel) 
		chargelevel = newlevel
		update_overlays()

/obj/machinery/power/tool_charger/examine(mob/user)
	..()
	if(charging)
		to_chat(user, "There's \a [charging] inside.")
		to_chat(user, "Current charge: [round(energy_charged / max_charge * 100)]%")

/obj/machinery/power/tool_charger/proc/turn_on()
	processing_objects.Add(src)
	turned_on = 1
	update_icon()
	set_light(1, 50, LIGHT_COLOR_HALOGEN)

/obj/machinery/power/tool_charger/proc/turn_off()
	turned_on = 0
	update_icon()
	set_light(0)