*** -PARAQUEST- Questionnaire analysis from Survey Solutions' paradata.
*** Sergiy Radyakin, The World Bank, 2022
*** sradyakin@@worldbank.org

program define do_processing
    version 17.0
	
	replace event="AnswerSet" if event=="AnswerRemoved"
	generate vname=substr(parameters,1,strpos(parameters,"||")-1) if event=="AnswerSet"
	assert !missing(vname) if event=="AnswerSet"
	drop parameters
	list

	drop if inlist(event, "VariableSet", "CommentSet")
	drop if inlist(event, "Restarted", "TranslationSwitched", "QuestionDeclaredValid", "QuestionDeclaredInvalid")

	count if (event=="ReceivedByInterviewer") & (event[_n-1]=="ReceivedBySupervisor")
	if r(N) > 0 {
		// this is partial synchronization (unsupported)
		drop if inlist(event, "ReceivedBySupervisor", "ReceivedByInterviewer") 
		noisily display as input "Interviews with partial synchronization are not supported."
		// todo: decide how to best handle this data
	}

	// Keep first completion session
	summarize order if event=="Resumed"
	drop if order<r(min)

	// NB! (does not take into account 'restarted')
	summarize order if event=="Completed" 
	drop if order>=r(min)
	
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
	
	list, sepby(v)
	
	drop if inlist(event, "Paused", "Resumed")
	replace ntime=eventtime[_n-1] if !missing(eventtime[_n-1])

	generate double duration=1000*(tottime-totwait) // in milliseconds
	//assert duration>=0
	
	list, sepby(v)
	susotime readable_duration duration, generate(dt) short

	//drop wait pevt v ntime dur // order
	list

	collapse (sum)duration , by(/* interview__id*/  responsible vname)
	susotime readable_duration duration, generate(dt) short
	list
	assert !missing(vname)
end

program define inject_duration
    version 12.0
	syntax , ///
	  file(string) ///        filename for questionnaire document in HTML format
	  variable(string) ///    variable name for column containing question varnames
	  duration(string) ///    variable name for column containing calculated duration for questions
	  ninterviews(string)  // variable name for column containing number of interviews where the question was answered   
	  
	// variable and duration are columns in the current data
	tempfile t1 t2
	copy `"`file'"' `"`t1'"'
 	isid `variable'
	forval i=1/`=_N' {
		
		local ivariable=`variable'[`i']
		local iduration=`duration'[`i']
		local ininterviews=`ninterviews'[`i']
		
		quietly _inject_duration , ifile(`"`t1'"') ofile(`"`t2'"') ///
		                           variable(`"`ivariable'"') ///
								   duration(`"`iduration'"') ///
								   ninterviews(`ininterviews')
		local t3 `"`t1'"'
		local t1 `"`t2'"'
		local t2 `"`t3'"'
		local t3 ""
		
	}
	
	copy `"`t2'"' `"`file'"', replace
	
end

program define _inject_duration
    // internal: do not call directly, call inject_duration instead
    version 12.0
	syntax , ifile(string) ofile(string) variable(string) duration(string) ninterviews(int)

    filefilter "`ifile'" "`ofile'", ///
       from(`"<div class="variable_name">`variable'</div>"') ///
       to(`"<div class="variable_name"><BIG> &nbsp;  <FONT Color="yellow"><span style="background-color:currentColor"><span style="color:navy">&nbsp;τ = `duration'&nbsp;[`ninterviews']</span></span></FONT></BIG></div><div class="variable_name">`variable'</div>"') replace
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



program define paraquest

    version 16.0     // version 16 is required because of the frames
	
	capture which susotime
	if _rc {
		display as error "Error! Requires Stata package -susotime-!"
		display as text `"You can download Stata package -susotime- from {browse "https://github.com/radyakin/susotime"}"'
	}	
	
	syntax anything

	pwf
	local cf "`r(currentframe)'"

	// Read-in paradata
	// local debug="GUID" // restrict to one interview here (if necessary)

	local cdir "`c(pwd)'"
	adopath ++ "`cdir'"

	local wf `anything'
	
	cd `"`wf'"'
	do "paradata.do"
	cd `"`cdir'"'

	local mode="quietly"
	if (`"`debug'"'!="") {
		keep if (interview__id==`"`debug'"')
		local mode="noisily"
	}

	frame copy `cf' paradata
	frame copy `cf' toc
	frame change toc
	contract interview__id
	quietly count
	
	display in green "Processing {result:`=r(N)'} interviews{break}"

	forval qqq=1/`=_N' {
		frame change toc
		local interviewid=interview__id[`qqq']
		display in green `"`interviewid'"'
		
		frame copy paradata work, replace
		frame change work
		quietly keep if (interview__id==`"`interviewid'"')
		drop interview__id
		// ...... do processing
		timer on 1
		`mode' do_processing
		timer off 1
		
		quietly _frappend , to(RESULT)	
	}

	display in green "Finished processing interviews"
	timer list
	
	display in green "Aggregating results"
	frame change RESULT
	count

	quietly count if duration<0	
	local d=r(N)
	if (`d' > 0) {
		display "==========="
		display "Dropping `d' observations with negative duration"
		drop if duration<0
	}

	collapse (mean) duration = duration ///
			 (sd) sd_duration=duration  ///
			 (count) n_duration=duration, ///
		by(vname)
		
	label variable n_duration "N interviews with response"
			 
	// round up to the nearest second
	replace duration=int(duration/1000)*1000
	susotime readable_duration duration, generate(dt) vshort //msec
	
	display in green "Creating questionnaire document with questions' timings"

	timer on 2
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
	                  duration("dt")  ninterviews("n_duration")
	timer off 2
	timer list
	
	display " {break} {break}"
	
	display `"Click {browse "`new'" :here} to open the questionnaire document."'
end


/* END OF FILE */
