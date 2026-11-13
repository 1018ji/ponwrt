# SPDX-License-Identifier: GPL-2.0-only
# Input is passive driver snapshots. No shell commands are executed here.
function trim(v) { sub(/^[ \t\r]+/, "", v); sub(/[ \t\r]+$/, "", v); return v }
function note(level, text) {
	print level ": " text
	if (level == "FAIL") failures++
	if (level == "WARN") warnings++
	messages[++nm] = level ": " text
}
function quote(v,    i, c, out) {
	out = "\""
	for (i = 1; i <= length(v); i++) {
		c = substr(v,i,1)
		if (c == "\\") out = out "\\\\"
		else if (c == "\"") out = out "\\\""
		else if (c == "\r") out = out "\\r"
		else if (c == "\n") out = out "\\n"
		else if (c == "\t") out = out "\\t"
		else out = out c
	}
	return out "\""
}
function u32(v) { return v ~ /^[0-9]+$/ && length(v) <= 10 && v + 0 <= 4294967295 }
function delta(a, b) { return b >= a ? b - a : 4294967296 - a + b }
function valid(s, p,    i, k, v) {
	if (bad[s,p]) return 0
	for (i = 1; i <= nr; i++) if (!((s SUBSEP p SUBSEP required[i]) in values)) return 0
	if (values[s,p,"format"] != "1" || values[s,p,"counter_bits"] != "32") return 0
	v = values[s,p,"instance"]
	if (v !~ /^[0-9]+$/ || length(v) > 20 || v ~ /^0+$/) return 0
	for (k in boolean) if (values[s,p,k] !~ /^[01]$/) return 0
	for (k in counter) if (!u32(values[s,p,k])) return 0
	if (values[s,p,"chip_id"] !~ /^[0-9a-f]+$/ || length(values[s,p,"chip_id"]) != 4) return 0
	if (values[s,p,"rx_forwarding"] != "linux" && values[s,p,"rx_forwarding"] != "native") return 0
	if ((values[s,p,"rx_legacy"] == "1") != (values[s,p,"rx_forwarding"] == "linux")) return 0
	return values[s,p,"rx_queues"] ~ /^[012]$/ && values[s,p,"rx_stopped"] ~ /^[0-3]$/
}
function rx_mode(mode) { return mode == "rx" || mode == "combined" }
function wed_mode(mode) { return mode == "wed" || mode == "combined" }
function mode_name(rx, tx) { return rx ? (tx ? "combined" : "rx") : (tx ? "wed" : "native") }
BEGIN {
	if (ENVIRON["HG_REPORT_DIR"] == "") {fatal=1; print "Missing report directory" > "/dev/stderr"; exit 64}
	expect = ENVIRON["HG_EXPECT"]; count = ENVIRON["HG_SAMPLES"] + 0
	dt_known = ENVIRON["HG_DT_KNOWN"] + 0
	dt_rx = ENVIRON["HG_DT_RX"] + 0; dt_wed = ENVIRON["HG_DT_WED"] + 0
	require_traffic = ENVIRON["HG_REQUIRE_TRAFFIC"] + 0
	json_file = ENVIRON["HG_REPORT_DIR"] "/summary.json"
	nr = split("format instance chip_id expected_rx expected_wed rx_legacy rx_configured rx_failed rx_quarantined rx_queues rx_stopped rx_host_packets rx_host_errors tx_wed tx_airoha tx_running tx_quarantined tx_counters_valid tx_mib0 tx_mib1 counter_bits wm_reset_count wa_reset_count recovering rx_forwarding", required, " ")
	n = split("expected_rx expected_wed rx_legacy rx_configured rx_failed rx_quarantined tx_wed tx_airoha tx_running tx_quarantined tx_counters_valid recovering", fields, " ")
	for (i = 1; i <= n; i++) boolean[fields[i]] = 1
	n = split("rx_host_packets rx_host_errors tx_mib0 tx_mib1 wm_reset_count wa_reset_count", fields, " ")
	for (i = 1; i <= n; i++) counter[fields[i]] = 1
}
FILENAME ~ /\/logs\/dmesg\.exit$/ { if ($0 + 0 != 0) log_unavailable=1; next }
FILENAME ~ /\/logs\/dmesg\.stderr$/ { if (trim($0) != "") log_unavailable=1; next }
FILENAME ~ /\/logs\/dmesg\.txt$/ {
	line = tolower($0)
	if (line ~ /txcoherent|legacy npu.*(failed|retained)|wed.*(exception|reset did not complete)|npu.*watchdog|mt7915.*message.*timeout/ && !log_seen[$0]++) log_errors++
	next
}
FILENAME ~ /\/wed-enable\.txt$/ {
	line = trim($0)
	if (line ~ /^(N|n|0)$/) parameter_disabled = 1
	next
}
FILENAME ~ /\/status\/[^\/]+\.txt$/ {
	if (FNR == 1) {
		n = split(FILENAME, path, "/")
		phy = path[n]; sub(/\.txt$/, "", phy)
		sample = path[n-2]; sub(/^sample-/, "", sample); sample += 0
		if (!(phy in have_phy)) { have_phy[phy] = 1; order[++np] = phy }
		if (sample > last[phy]) last[phy] = sample
		if (!first[phy] || sample < first[phy]) first[phy] = sample
	}
	pos = index($0, ":")
	if (!pos) { bad[sample,phy] = 1; next }
	key = trim(substr($0,1,pos-1)); value = trim(substr($0,pos+1))
	if (key !~ /^[a-z0-9_]+$/ || ((sample SUBSEP phy SUBSEP key) in values)) bad[sample,phy] = 1
	values[sample,phy,key] = value
	next
}
END {
	if (fatal) exit 64
	print "HG5585F passive offload check"
	print "RX counters count frames returned by NPU to Linux; WED MIBs count hardware progress."
	print "Two PHY views may share one device instance. Their counters must not be added."
	if (expect != "auto" && dt_known && (rx_mode(expect) != dt_rx || wed_mode(expect) != dt_wed))
		note("FAIL", "Requested mode " expect " disagrees with selected device-tree mode " mode_name(dt_rx,dt_wed))
	for (pi = 1; pi <= np; pi++) {
		p = order[pi]; s = last[p]; b = first[p]
		if (s != count) { note("WARN", p ": status disappeared before the final snapshot"); continue }
		if (!valid(s,p)) { note("WARN", p ": incomplete, unreadable or unsupported status format"); continue }
		if (values[s,p,"chip_id"] != "7906") { note("SKIP", p ": not an MT7916 view"); continue }
		checked++
		mode = expect == "auto" ? mode_name(values[s,p,"expected_rx"]+0,values[s,p,"expected_wed"]+0) : expect
		r = rx_mode(mode); w = wed_mode(mode); needed += r + w
		view[++nv] = p; view_mode[nv] = mode; view_instance[nv] = values[s,p,"instance"]
		rx_delta[nv] = tx_delta[nv] = error_delta[nv] = "null"
		print "VIEW " p ": mode=" mode ", instance=" values[s,p,"instance"] ", RX forwarding=" values[s,p,"rx_forwarding"]
		if ((values[s,p,"rx_quarantined"]+0) || (values[s,p,"tx_quarantined"]+0)) note("FAIL", p ": DMA quarantined; resources retained, restart forbidden")
		if ((values[s,p,"rx_failed"]+0)) note("FAIL", p ": NPU state synchronization failed")
		if ((values[s,p,"rx_stopped"]+0)) note("FAIL", p ": an NPU host return queue is stopped")
		if (r && !(values[s,p,"rx_legacy"]+0)) note("FAIL", p ": requested legacy RX backend is not attached")
		if (w && (!(values[s,p,"tx_wed"]+0) || !(values[s,p,"tx_airoha"]+0))) note("FAIL", p ": requested Airoha WED provider is not attached")
		if (r && (values[s,p,"rx_configured"]+0) && (values[s,p,"rx_queues"]+0) == 0) note("FAIL", p ": configured NPU RX has no host return queues")
		if ((values[s,p,"recovering"]+0)) note("WARN", p ": recovery in progress; activity cannot be confirmed")
		if (r && !(values[s,p,"rx_configured"]+0)) note("WARN", p ": NPU receive path is not configured or is quiesced")
		if (w && (values[s,p,"tx_wed"]+0) && !(values[s,p,"tx_running"]+0)) note("WARN", p ": WED is attached but quiesced")
		if (!r && !w) { note("SKIP", p ": native mode selected; no offload requested"); continue }
		if (b == s || !valid(b,p)) { note("WARN", p ": no valid initial counter snapshot"); continue }
		unstable = missing = rx_inactive = tx_unreadable = 0
		for (t = b; t <= s; t++) {
			if (!valid(t,p)) { missing=1; continue }
			if (("i" values[t,p,"instance"]) != ("i" values[s,p,"instance"]) ||
			    values[t,p,"wm_reset_count"] != values[s,p,"wm_reset_count"] ||
			    values[t,p,"wa_reset_count"] != values[s,p,"wa_reset_count"] ||
			    (values[t,p,"recovering"]+0)) unstable=1
			if (t < s && ("i" values[t,p,"instance"]) == ("i" values[s,p,"instance"]) &&
			    ((values[t,p,"rx_quarantined"]+0) || (values[t,p,"tx_quarantined"]+0)))
				note("FAIL", p ": a terminal DMA fault was recorded in this driver instance")
			if (t < s && ((values[t,p,"rx_failed"]+0) || (values[t,p,"rx_stopped"]+0))) unstable=1
			if (!(values[t,p,"rx_configured"]+0)) rx_inactive=1
			if (!(values[t,p,"tx_counters_valid"]+0) || !(values[t,p,"tx_running"]+0)) tx_unreadable=1
		}
		if (missing) { note("WARN", p ": an intermediate status snapshot is missing or invalid"); continue }
		if (unstable) {
			note("WARN", p ": driver reload or recovery crossed the sampling window; deltas omitted")
			continue
		}
		if (r && rx_inactive) note("WARN", p ": RX was quiesced during sampling; delta omitted")
		if (r && !rx_inactive) {
			d = e = 0
			for (t = b+1; t <= s; t++) {
				d += delta(values[t-1,p,"rx_host_packets"]+0,values[t,p,"rx_host_packets"]+0)
				e += delta(values[t-1,p,"rx_host_errors"]+0,values[t,p,"rx_host_errors"]+0)
			}
			rx_delta[nv] = sprintf("%.0f",d); error_delta[nv] = sprintf("%.0f",e)
			print "RX " p ": host_frames_delta=" rx_delta[nv] ", errors_delta=" error_delta[nv]
			if (d > 0) observed++; else if (require_traffic) note("WARN", p ": no NPU receive progress observed; traffic is required")
			if (e > 0) note("WARN", p ": NPU host delivery errors increased")
		}
		if (w) {
			if (tx_unreadable) {
				note("WARN", p ": WED counters unavailable (quiesced, recovering or read-clear mode)")
			} else {
				d = 0
				for (t = b+1; t <= s; t++)
					d += delta(values[t-1,p,"tx_mib0"]+0,values[t,p,"tx_mib0"]+0) + delta(values[t-1,p,"tx_mib1"]+0,values[t,p,"tx_mib1"]+0)
				tx_delta[nv] = sprintf("%.0f",d)
				print "TX " p ": wed_mib_delta=" tx_delta[nv]
				if (d > 0) observed++; else if (require_traffic) note("WARN", p ": no WED transmit progress observed; traffic is required")
			}
		}
	}
	if (checked && !needed && dt_known && (dt_rx || dt_wed))
		note("WARN", "Device tree requests offload but no matching requested controller view was found")
	if (!checked) {
		note("WARN", "No usable offload_status; check debugfs, driver version and PHY selection")
	}
	if (parameter_disabled && (wed_mode(expect) || (expect == "auto" && dt_wed)))
		note("FAIL", "WED requested but mt7915e.wed_enable is disabled")
	if (log_errors) note("WARN", "Kernel log contains offload/DMA errors; inspect sample-*/logs/dmesg.txt")
	if (log_unavailable) note("WARN", "Kernel log collection is incomplete; inspect logs/dmesg.stderr and .exit")
	result = failures ? "FAIL" : warnings ? "WARN" : !needed ? "SKIP" : observed == needed ? "PASS" : "READY"
	code = failures ? 1 : warnings ? 2 : 0
	if (result == "READY") print "READY: required paths are configured; idle counters do not prove forwarding or throughput."
	print "RESULT: " result
	print "Full RX-to-PPE forwarding and actual radio throughput are not asserted by this check."
	print "{\"format\":1,\"result\":" quote(result) ",\"exit_code\":" code ",\"expected\":" quote(expect) ",\"views\":[" > json_file
	for (i = 1; i <= nv; i++) {
		if (i > 1) printf ",\n" > json_file
		printf "{\"phy\":%s,\"instance\":%s,\"mode\":%s,\"rx_host_delta\":%s,\"rx_errors_delta\":%s,\"wed_tx_delta\":%s}", quote(view[i]),quote(view_instance[i]),quote(view_mode[i]),rx_delta[i],error_delta[i],tx_delta[i] > json_file
	}
	print "],\"messages\":[" > json_file
	for (i = 1; i <= nm; i++) printf "%s%s", (i > 1 ? "," : ""), quote(messages[i]) > json_file
	print "]}" > json_file
	close(json_file)
	exit code
}
