*** -PARAQUEST- Questionnaire analysis from Survey Solutions' paradata.
*** Sergiy Radyakin, The World Bank, 2022
*** sradyakin@@worldbank.org

program define paraquestversion, rclass
	return local version "1.00"
end

program define aboutparaquest

	paraquestversion
	local v=r(version)

	display " {break}"
	display as text "PARAQUEST version {result:`v'}"
	display as text "Sergiy Radyakin, The World Bank, 2022"
	display as text `"`="sradyakin"+"@"+"worldbank.org"'"'
	display " {break}"
end

program define do_processing
	// Do processing of one interview
	version 17.0

	syntax , [debug(string)]

	replace event="AnswerSet" if event=="AnswerRemoved" | event=="CommentSet"

	generate vname = substr(parameters, 1, strpos(parameters,"||")-1) ///
		if inlist(event, "AnswerSet", "VariableEnabled", "VariableDisabled")

	assert !missing(vname) if event=="AnswerSet"
	drop parameters
	if ("`debug'"!="") list

	// Keep first completion session
	summarize order if event=="Resumed"
	drop if order<r(min)

	// NB! (does not take into account 'restarted')
	summarize order if event=="Completed" 
	drop if order>=r(min)

	count if (event=="ReceivedByInterviewer") & (event[_n-1]=="ReceivedBySupervisor")
	if r(N) > 0 {
		// this is partial synchronization (unsupported)
		drop if inlist(event, "ReceivedBySupervisor", "ReceivedByInterviewer") 
		noisily display as input "Interviews with partial synchronization are not supported."
		// todo: decide how to best handle this data
	}

	count if event=="AnswerSet"
	if (r(N)==0) {
		drop *
		display in yellow " - SKIPPED"
		exit
	}

	generate double eventtime = clock(subinstr(timestamp_utc,"T"," ",.), "YMDhms")
	format eventtime %tc
	drop timestamp_utc tz_offset

	generate double ntime=eventtime[_n-1]
	replace ntime=eventtime in 1
	format ntime %tc

	generate long pevt=1 in 1
	replace pevt = cond(event=="AnswerSet", pevt[_n-1]+1 , pevt[_n-1]) in 2/L
	generate long v=pevt[_n-1]

	generate double wait=0 // milliseconds
	replace wait = (eventtime-eventtime[_n-1])/1000 if event=="Resumed"
	egen totwait=total(wait), by(v)
	format totwait %21.0g

	generate etime=(eventtime-ntime)/1000
	egen tottime=total(etime), by(v)
	format tottime %21.0g
	generate rtime=etime-wait

	if ("`debug'"!="") list, sepby(v)

	drop if inlist(event, "Paused", "Resumed")
	replace ntime=eventtime[_n-1] if !missing(eventtime[_n-1])

	generate double duration=1000*(tottime-totwait) // in milliseconds

	if ("`debug'"!="") list, sepby(v)
	if ("`debug'"!="") susotime readable_duration duration, generate(dt) short

	if ("`debug'"!="") list, sepby(v)

	collapse (sum)duration , by(responsible vname)
	
	susotime readable_duration duration, generate(dt) short
	if ("`debug'"!="") list
	assert !missing(vname)
end

program define inject_duration
	version 12.0

	// in below @ denotes "variable name for column containing ..."

	syntax , ///
	  file(string)        /// filename for questionnaire document in HTML format
	  variable(string)    /// @ question varnames
	  duration(string)    /// @ calculated duration for questions
	  ninterviews(string) /// @ number of interviews where the question was answered
	  tcontrib(string)    /// @ time that this question contributes to the average interview duration
	  qperc(string)       /// @ percent of time of the average interview duration that is attributable to this question.
	  stats(string)       //  which statistics to include into the report

	// variable and duration are columns in the current data
	tempfile t1 t2
	copy `"`file'"' `"`t1'"'
	isid `variable'
	forval i=1/`=_N' {

		local ivariable=`variable'[`i']
		local iduration=`duration'[`i']
		local ininterviews=`ninterviews'[`i']
		local itcontrib=`tcontrib'[`i']
		local iqperc=`qperc'[`i']

		quietly _inject_duration , ifile(`"`t1'"') ofile(`"`t2'"') ///
								   variable(`"`ivariable'"') ///
								   duration(`"`iduration'"') ///
								   ninterviews(`ininterviews') ///
								   tcontrib(`"`itcontrib'"') ///
								   qperc(`"`iqperc'"') stats(`"`stats'"')

		local t3 `"`t1'"'
		local t1 `"`t2'"'
		local t2 `"`t3'"'
		local t3 ""

	}

	write_footer, ifile(`"`t1'"') ofile(`"`file'"')

end

program define write_footer

	version 12.0
	syntax , ifile(string) ofile(string)
	
	local ts="$S_DATE $S_TIME"
	paraquestversion
	local v=r(version)
	
	tempfile tmp
	
	filefilter "`ifile'" "`tmp'", replace ///
		from(`"</body>"') ///
		to(`"<article class="appendix_section paraquest"><h2 id="paraquest_appendix"><FONT Color="yellow"><span style="background-color:currentColor"><span style="color:navy">PARAQUEST</span></span></FONT></h2><section><P><FONT Color="yellow"><span style="background-color:currentColor"><span style="color:navy">Produced with Paraquest version `v' on `ts'.</span></span></FONT></P></section></article></body>"')

	capture assert (r(occurrences)==1)
	if _rc {
		display in red "Error! Legend not found in the questionnaire file. "
		error 9
	}
	
	
	// write a link to jump to the newly added section
	
	filefilter "`tmp'" "`ofile'", replace ///
		from(`"class="section_name appendix">Legend</a>"') ///
		to(`"class="section_name appendix">Legend</a></dd><dt>&nbsp;</dt><dd><a href="#paraquest_appendix" class="section_name appendix">Paraquest</a> "')

	capture assert (r(occurrences)==1)
	if _rc {
		display in red "Error! Table of contents entry not found in the questionnaire file. "
		error 9
	}

end


program define _inject_duration
    // internal: do not call directly, call inject_duration instead
    version 12.0
	syntax , ifile(string) ofile(string) variable(string) ///
			 duration(string) ninterviews(int) ///
			 tcontrib(string) qperc(string) stats(string)

	local style1 `"<FONT Color="yellow"><span style="background-color:currentColor"><span style="color:navy">"'
	local style2 `"</span></span></FONT>"'

	local block_tquestion = ///
	  cond(strpos(`" `stats' "', " tquestion ")>0, `"`style1'&tau;=`duration'`style2'"',"")

	local block_ninterviews = ///
	  cond(strpos(`" `stats' "', " ninterviews ")>0 ,`"`style1'&nu;=`ninterviews'`style2'"',`""')

	local block_tcontrib = ///
	  cond(strpos(`" `stats' "', " tcontrib ")>0, `"`style1'&chi;=`tcontrib'`style2'"', `""')

	local block_psurvey = ///
	  cond(strpos(`" `stats' "', " psurvey ")>0, `"`style1'&delta;=`qperc'`style2'"', `""')

	local newtext=`"`block_tquestion'"'
	if (`"`newtext'"'!="") local newtext=`"`newtext'<BR>`block_ninterviews'"'
	else local newtext=`"`block_ninterviews'"'
	if (`"`newtext'"'!="") local newtext=`"`newtext'<BR>`block_tcontrib'"'
	else local newtext=`"`block_tcontrib'"'
	if (`"`newtext'"'!="") local newtext=`"`newtext'<BR>`block_psurvey'"'
	else local newtext=`"`block_psurvey'"'

	filefilter "`ifile'" "`ofile'", ///
		from(`"<div class="variable_name">`variable'</div>"') ///
		to(`"<div class="variable_name"><BIG>`newtext'</BIG></div><div class="variable_name">`variable'</div>"') replace

	capture assert (r(occurrences)==1)
	if _rc {
		display in red "Error! Variable '`variable'' not found in the questionnaire file. "
		error 9
	}
end

program define _frappend
	version 16.0
	syntax , to(string)

	quietly count
	if (r(N)==0) {
		display in yellow "Nothing to append. Exiting."
		exit
	}

	capture confirm frame `to'
	if (_rc) {
	  display in green "Frame `to' created."
	  quietly frame create `to'
	}

	capture {
		tempfile tmp
		save `"`tmp'"'
		frame `to' : append using `"`tmp'"'
	}
end	

program define loadparadata

	// Load paradata from current directory

	version 16.0

	tempfile tmp

	filefilter "paradata.do" `"`tmp'"', ///
	  from(`"insheet using "paradata.tab", tab case names"') ///
	  to(`"import delimited "paradata.tab"`=char(10)'`=char(13)'capture rename ïinterview__id interview__id"')

	do `"`tmp'"'
end


program define inspectparadata

	// Verify paradata doesn't contain any unknown events

	version 16.0

	assert inlist(event, ///
		"AnswerRemoved", "AnswerSet", "ApproveByHeadquarter", ///
		"ApproveBySupervisor", "ClosedBySupervisor", "CommentSet", ///
		"Completed", "InterviewCreated", "InterviewModeChanged") | ///
		///
		inlist(event, ///
		"InterviewerAssigned", "KeyAssigned", "OpenedBySupervisor", ///
		"Paused", "QuestionDeclaredInvalid", "QuestionDeclaredValid", ///
		"ReceivedByInterviewer", "ReceivedBySupervisor", ///
		"RejectedByHeadquarter") | ///
		///
		inlist(event, ///
		"RejectedBySupervisor", "Restarted", "Resumed", ///
		"SupervisorAssigned", "TranslationSwitched", ///
		"UnapproveByHeadquarters", "VariableDisabled", ///
		"VariableEnabled", "VariableSet")

end

program define reduceevents

	// Preliminary deletion of events which will not be processed 
	// to reduce the volume of data

	version 16.0

	drop if inlist(event, ///
		"VariableSet", "VariableEnabled", "VariableDisabled", ///
		"Restarted", "TranslationSwitched", ///
		"QuestionDeclaredValid", "QuestionDeclaredInvalid")
end

program define paraquest

	version 16.0     // version 16 is required because of the frames
	
	local paraquest_started=clock("$S_DATE $S_TIME","DMYhms")

	aboutparaquest
	
	capture which susotime
	if _rc {
		display as error "Error! Requires Stata package -susotime-!"
		display as text `"You can download Stata package -susotime- from {browse "https://github.com/radyakin/susotime"}"'
		error 111
	}
	capture susotime

	syntax anything, [  ///
	  debug(string)     ///    "GUID" restrict to one interview here (if necessary)
	  limit(integer -1) ///    Read no more than specified number of interviews or all (for -1)
	  stats(string)]    //     Report specific statistics only 

	// Stats is: tquestion, tsurvey, psurvey, ninterviews
	if missing(`"`stats'"') local stats="tquestion"
	// check options
	foreach w in `stats' {
	    if (!inlist("`w'", "tquestion", "ninterviews", "tcontrib", "psurvey")) {
		    display as error "Option stats() incorrectly specified."
			error 198
		}
	}

	if ((`limit'<0) & (`limit'!=-1)) {
		display as error "Option limit() incorrectly specified."
		display as error "Invalid value of the limit, use a non-negative limit or a value -1 for no limit!"
		error 198
	}

	quietly pwf
	local cf "`r(currentframe)'"

	// Read-in paradata
	local cdir "`c(pwd)'"

	local wf `anything'

	cd `"`wf'"'
	capture loadparadata
	local retcode=_rc
	cd `"`cdir'"'
	
	if (`retcode'==111) {
		// below texts are duplications of what the modern version of 
		// Survey Solutions would describe those columns.
		label variable tz_offset `"Timezone offset relative to UTC"'
		label variable parameters `"Event-specific parameters"'
	}

	inspectparadata

	local mode="quietly"
	if (`"`debug'"'!="") {
		keep if (interview__id==`"`debug'"')
		local mode="noisily"
	}

	reduceevents

	// todo: this is expensive - 3 copies of the data
	frame copy `cf' paradata
	frame put interview__id, into(toc) // just one variable
	frame change toc
	contract interview__id
	quietly count

	local bigN=c(N)
	if (`limit'>=0) local bigN=min(c(N), `limit')
	local paraquest_loaded=clock("$S_DATE $S_TIME","DMYhms")

	display in green "Processing {result:`bigN'} interviews:{break}"

	forval qqq=1/`bigN' {
		frame change toc
		local interviewid=interview__id[`qqq']
		
		local ni=string(`qqq',"%7.0f")
		while (strlen(`"`ni'"')<7) {
		    local ni=`" `ni'"'
		}
		
		local p=string(`qqq'/`=_N'*100,"%6.2f")
		if (strlen(`"`p'"')<6) local p=`" `p'"'
		if (strlen(`"`p'"')<6) local p=`" `p'"'
		display in green `"`ni' `interviewid' "' "`p'%"

		quietly frame copy paradata work, replace
		frame change work
		quietly keep if (interview__id==`"`interviewid'"')
		drop interview__id
		// ...... do processing
		`mode' do_processing, debug(`"`debug'"')

		`mode' _frappend , to(RESULT)	

		if (`qqq'>`limit' & `limit'>=0) continue, break
	}

	display in green "Finished processing interviews!{break}"
	local paraquest_processed=clock("$S_DATE $S_TIME","DMYhms")

	display in green "Aggregating results"
	frame change RESULT
	count

	quietly count if duration<0	
	local d=r(N)
	if (`d' > 0) {
		display "==========="
		display "Dropping `d' observations with negative duration"
		list if duration<0
		drop if duration<0
	}

	collapse (mean) duration = duration ///
			 (sd) sd_duration=duration  ///
			 (count) n_duration=duration, ///
		by(vname)

	label variable n_duration "N interviews with response"

	quietly {
		// round up to the nearest second
		replace duration=int(duration/1000)*1000
		susotime readable_duration duration, generate(dt) vshort // msec

		generate double contrib = duration * n_duration/`bigN'
		susotime readable_duration contrib, generate(dtexp) vshort

		summarize contrib, meanonly
		local avgtime=r(sum)
		generate perc = string(contrib/`avgtime' * 100,"%8.4f")+"%"	 // in percent
	}

	display in green "Creating questionnaire document with questions' timings"

	local paraquest_aggregated=clock("$S_DATE $S_TIME","DMYhms")
	local new `""output.html""' // fixed output name
	local flist `"`: dir "`wf'" files "*.html"'"'
	local result : list flist-new
	assert `: list sizeof result' == 1

	local result `result'
	local new `new'

	local orig=`"`wf'\`result'"'
	local new =`"`wf'\`new'"'

	copy `"`orig'"' `"`new'"', replace
	inject_duration , file(`"`new'"') variable("vname") ///
					  duration("dt")  ninterviews("n_duration") ///
					  tcontrib("dtexp") qperc("perc") stats(`stats')
	
	local paraquest_reported=clock("$S_DATE $S_TIME","DMYhms")
	
	display " {break} {break}"
	display as text "Loading paradata: " as result ///
			clockdiff(`paraquest_started',`paraquest_loaded', "second") ///
			as text "s"
	display as text "Processing paradata: " as result ///
			clockdiff(`paraquest_loaded',`paraquest_aggregated', "second") ///
			as text "s"
	display as text "Writing report: " as result ///
			clockdiff(`paraquest_aggregated',`paraquest_reported', "second") ///
			as text "s"
	display " {break} {break}"

	display `"Click {browse "`new'" :here} to open the questionnaire document."'
end


/* END OF FILE */
