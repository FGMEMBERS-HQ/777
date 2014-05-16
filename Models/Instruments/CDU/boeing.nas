var input = func(v) {
		setprop("instrumentation/cdu/input",getprop("instrumentation/cdu/input")~v);
	}
	
var input = func(v) {
		setprop("instrumentation/cdu/input",getprop("instrumentation/cdu/input")~v);
	}
  
var cduWpOffset = 0;
var cduWpSelected = -1;

var cduLegsDeleteWP = func(pos) {
  var index = pos + cduWpOffset;
  setprop("autopilot/route-manager/input","@DELETE"~index);
  #print("DEBUG: Delete WP at position ", index, ", (offset=", cduWpOffset, ")");
}

var cduLegsInsertWP = func(pos, fix) {
  var index = pos + cduWpOffset;
  setprop("autopilot/route-manager/input","@INSERT"~index~":"~fix);
  #print("DEBUG: Insert WP '", fix, "' at position ", index, ", (offset=", cduWpOffset, ")");
}

var cduLegsSetAltWP = func(pos, altitude) {
  var index = pos + cduWpOffset;
  #print("DEBUG: Set altitute ", altitude, " of WP ", index, ", (offset=", cduWpOffset, ")");
  setprop("autopilot/route-manager/route/wp["~index~"]/altitude-ft",altitude);
  if (substr(altitude,0,2) == "FL"){
    setprop("autopilot/route-manager/route/wp["~index~"]/altitude-ft",substr(altitude,2)*100);
  }
}

var cduLegsScrollWP = func(relative) {
  var index = cduWpOffset + relative;
  var numberOfWPs = size(props.globals.getNode("autopilot/route-manager/route").getChildren("wp"));
  
  #print("DEBUG: cduLegsScrollWP newIndex=", index, ", numberOfWPs=", numberOfWPs);
  if (index < 0) {
    cduWpOffset = 0;
  }
  else if (index < numberOfWPs-4) {
    cduWpOffset = index;
  }
  #print("DEBUG: cduLegsScrollWP new cduWpOffset=", cduWpOffset);
}

var cduLegsLeftLSKPressed = func(index, cduInput) {
  cduWpSelected = -1;
  if (cduInput == nil or cduInput == "") {
    var wpIndex = cduWpOffset + index;
    var curWp = getprop("autopilot/route-manager/route/wp["~wpIndex~"]/id");
    if ( curWp != nil){
      cduWpSelected = wpIndex;
      return curWp;
    }
    else {
      return "";
    }
  } 
  else if (cduInput == "DELETE"){
    cduLegsDeleteWP(index);
    return "";
  }
  else {
    cduLegsInsertWP(index, cduInput);
    return "";
  }
}

var cduSelectWaypoint = func(wpIndex, cduInput) {
  if (wpIndex>0) {
    var wpId = getprop("autopilot/route-manager/route/wp["~wpIndex~"]/id");
    if (wpId != nil or wpId == cduInput) {
      setprop("autopilot/route-manager/current-wp", wpIndex);
      return "";
    }
  }
  return cduInput;
}

var cduHold = {
  active : 0,
  fix : "",
  hdg : 0,
  distance : 4.0,
  radius   : 1.0,
  turnLeft : 1,
  holdLegs : [],
  holdListenerID : nil,
  entryWP : -1,
  exitWP : -1,
  
  render : func(output) {
    output.title          = "HOLD";
    output.leftTitle[0]   = "Hold fix";
    output.left[0]        = me.fix;
    output.leftTitle[1]   = "Heading";
    output.left[1]        = sprintf("%3d",me.hdg);
    output.leftTitle[2]   = "Turn";
    output.left[2]        = (me.turnLeft) ? "LEFT" : "RIGHT"; 
    output.rightTitle[0]  = "Distance [nm]";
    output.right[0]       = sprintf("%2.1f", me.distance);
    output.rightTitle[1]  = "Width [nm]";
    output.right[1]       = sprintf("%2.1f", me.radius * 2);
    output.right[5]       = (me.active) ? "LEAVE HOLD>" : "ENTER HOLD>";    
  },
  
  lskPressed : func(key, cduInput) {
    if (key == "LSK1L") {
      me.fix = cduInput;
    }
    else if ( key == "LSK2L" ) {
      me.hdg = cduInput;
    }
    else if ( key == "LSK3L" ) {
      me.turnLeft = (me.turnLeft) ? 0 : 1;
      return cduInput;
    }
    else if ( key == "LSK1R" ) {
      me.distance = cduInput;
    }
    else if ( key == "LSK2R" ) {
      me.radius = cduInput / 2.0;
    }
    else if ( key == "LSK6R" ) {
      me.active = (me.active) ? 0 : 1;
      if (me.active) {
        
        me.createHoldWPs();
        
        var loop = func() {
          var cur = flightplan().current;
          if (cur == cduHold.exitWP-1 ) {
            print("DEBUG: CDU Hold, end of hold reached... preparing for another round!");
            cduHold.exitWP = cduHold.insertLegs( cduHold.holdLegs, cduHold.exitWP );
            setprop('autopilot/route-manager/current-wp', cur-1);
          }
          else {
            print("DEBUG: CDU Hold, loop on WP ", flightplan().current);
          }
        };
        me.holdListenerID = setlistener('/autopilot/route-manager/current-wp', loop);
        
      }
      else {
        if (me.holdListenerID != nil) {
          print("DEBUG: CDU Hold, deactivate hold.");
          removelistener(me.holdListenerID);
          
          # premature end... (if on the final leg of the hold)
          var oneLoopAhead = flightplan().current + size(cduHold.holdLegs);
          if (oneLoopAhead < me.exitWP) {
            print("DEBUG: CDU Hold, exiting hold earlier.");
            flightplan().current = oneLoopAhead;
          }
        }
      }
      return cduInput;
    }
    return "";
  },  
  
  createHoldWPs : func() {
    if (me.active) {
      # calculate waypoints...
      var turn = (me.turnLeft) ? 1 : -1;
      var alpha = turn * 63.4;
      var dH2 = 2.236 * me.radius;
      var beta = turn * 360 * math.atan2( 2 * me.radius , (me.radius + me.distance) ) / ( 2 * math.pi );
      var dH3 = math.sqrt( me.radius * me.radius * 4 + (me.radius + me.distance) * (me.radius + me.distance) );
      
      var _deg = func(hdg) { return (hdg < 0) ? (hdg + 360) : ( (hdg >= 360) ? (hdg - 360) : hdg ); }
      var _formatLeg = func(fix, hdg, dist) {
        return fix ~ "/" ~sprintf("%3d",hdg)~"/"~sprintf("%2.1f", dist);
      };
      # calculate WP 3 miles ahead
      var ahead = geo.Coord.new();
      ahead.set_latlon(getprop('position/latitude-deg'), getprop('position/longitude-deg'));
      ahead.apply_course_distance(getprop('orientation/heading-deg'), 3 * 1852 ); 
      
      var entryLeg = [
          ahead.lon()~','~ahead.lat(),
          _formatLeg(me.fix, _deg(me.hdg + 180), me.distance),
          me.fix
      ];
      
      me.holdLegs = [ 
          _formatLeg(me.fix, me.hdg, me.radius),
          _formatLeg(me.fix, _deg(me.hdg - alpha), dH2),
          _formatLeg(me.fix, _deg(me.hdg + 180 + beta), dH3),
          _formatLeg(me.fix, _deg(me.hdg + 180), me.distance + me.radius),
          me.fix,
      ];
      
      var curWpIdx = getprop("autopilot/route-manager/current-wp");
      
      me.entryWP = me.insertLegs(entryLeg, curWpIdx);
      me.exitWP = me.insertLegs(me.holdLegs, me.entryWP);
      
      setprop("autopilot/route-manager/current-wp", curWpIdx);
    }
  },
  
  insertLegs: func(legs, index) {
    for (i=0; i<size(legs); i += 1) {
      print("DEBUG: CDU Hold: Inserting HOLD at ", index + i , ": ", legs[i]);
      setprop("autopilot/route-manager/input","@INSERT"~(index + i)~":"~legs[i]);
    }
    return index + size(legs);
  }
};

var key = func(v) {
		var cduDisplay = getprop("instrumentation/cdu/display");
		var serviceable = getprop("instrumentation/cdu/serviceable");
		var eicasDisplay = getprop("instrumentation/eicas/display");
		var cduInput = getprop("instrumentation/cdu/input");
		
		if (serviceable == 1){
      # dispatch by page (new)
      if (cduDisplay == "HOLD") {
        cduInput = cduHold.lskPressed(v, cduInput);
      }
      else { # dispatch by key (old)  
        if (v == "LSK1L"){
          if (cduDisplay == "DEP_ARR_INDEX"){
            cduDisplay = "RTE1_DEP";
          }
          if (cduDisplay == "EICAS_MODES"){
            eicasDisplay = "ENG";
          }
          if (cduDisplay == "EICAS_SYN"){
            eicasDisplay = "ELEC";
          }
          if (cduDisplay == "INIT_REF"){
            cduDisplay = "IDENT";
          }
          if (cduDisplay == "NAV_RAD"){
            setprop("instrumentation/nav[0]/frequencies/selected-mhz",cduInput);
            cduInput = "";
          }
          if (cduDisplay == "RTE1_1"){
            setprop("autopilot/route-manager/departure/airport",cduInput);
            cduInput = "";
          }
          if (cduDisplay == "RTE1_LEGS"){
            cduInput = cduLegsLeftLSKPressed(1, cduInput);
          }
          if (cduDisplay == "TO_REF"){
            setprop("instrumentation/fmc/to-flap",cduInput);
            cduInput = "";
          }
        }
        if (v == "LSK1R"){
          if (cduDisplay == "EICAS_MODES"){
            eicasDisplay = "FUEL";
          }
          if (cduDisplay == "EICAS_SYN"){
            eicasDisplay = "HYD";
          }
          if (cduDisplay == "NAV_RAD"){
            setprop("instrumentation/nav[1]/frequencies/selected-mhz",cduInput);
            cduInput = "";
          }
          if (cduDisplay == "RTE1_1"){
            setprop("autopilot/route-manager/destination/airport",cduInput);
            cduInput = "";
          }
          if (cduDisplay == "RTE1_LEGS"){
            cduLegsSetAltWP(1, cduInput);
            cduInput = "";
          }
        }
        if (v == "LSK2L"){
          if (cduDisplay == "EICAS_MODES"){
            eicasDisplay = "STAT";
          }
          if (cduDisplay == "EICAS_SYN"){
            eicasDisplay = "ECS";
          }
          if (cduDisplay == "NAV_RAD"){
            setprop("instrumentation/nav[0]/radials/selected-deg",cduInput);
            cduInput = "";
          }
          if (cduDisplay == "POS_INIT"){
            setprop("instrumentation/fmc/ref-airport",cduInput);
            cduInput = "";;
          }
          if (cduDisplay == "INIT_REF"){
            cduDisplay = "POS_INIT";
          }
          if (cduDisplay == "RTE1_1"){
            setprop("autopilot/route-manager/departure/runway",cduInput);
            cduInput = "";;
          }
          if (cduDisplay == "RTE1_LEGS"){
            cduInput = cduLegsLeftLSKPressed(2, cduInput);
          }
        }
        if (v == "LSK2R"){
          if (cduDisplay == "DEP_ARR_INDEX"){
            cduDisplay = "RTE1_ARR";
          }
          else if (cduDisplay == "EICAS_MODES"){
            eicasDisplay = "GEAR";
          }
          else if (cduDisplay == "EICAS_SYN"){
            eicasDisplay = "DRS";
          }
          if (cduDisplay == "NAV_RAD"){
            setprop("instrumentation/nav[1]/radials/selected-deg",cduInput);
            cduInput = "";
          }
          else if (cduDisplay == "MENU"){
            eicasDisplay = "EICAS_MODES";
          }
          else if (cduDisplay == "RTE1_LEGS"){
            cduLegsSetAltWP(2, cduInput);
            cduInput = "";
          }
        }
        if (v == "LSK3L"){
          if (cduDisplay == "INIT_REF"){
            cduDisplay = "PERF_INIT";
          }
          if (cduDisplay == "RTE1_LEGS"){
            cduInput = cduLegsLeftLSKPressed(3, cduInput);
          }
        }
        if (v == "LSK3R"){
          if (cduDisplay == "RTE1_LEGS"){
            cduLegsSetAltWP(3, cduInput);
            cduInput = "";
          }
        }
        if (v == "LSK4L"){
          if (cduDisplay == "INIT_REF"){
            cduDisplay = "THR_LIM";
          }
          if (cduDisplay == "RTE1_LEGS"){
            cduInput = cduLegsLeftLSKPressed(4, cduInput);
          }
        }
        if (v == "LSK4R"){
          if (cduDisplay == "RTE1_LEGS"){
            cduLegsSetAltWP(4, cduInput);
            cduInput = "";
          }
        }
        if (v == "LSK5L"){
          if (cduDisplay == "INIT_REF"){
            cduDisplay = "TO_REF";
          }
          if (cduDisplay == "RTE1_LEGS"){
            cduInput = cduLegsLeftLSKPressed(5, cduInput);
          }
        }
        if (v == "LSK5R"){
          if (cduDisplay == "RTE1_LEGS"){
            cduLegsSetAltWP(5, cduInput);
            cduInput = "";
          }
          if (cduDisplay == "NAV_RAD") {
            var nav0freq = getprop("instrumentation/nav[0]/frequencies/selected-mhz");
            var nav0rad = getprop("instrumentation/nav[0]/radials/selected-deg");
            var nav1freq = getprop("instrumentation/nav[1]/frequencies/selected-mhz");
            var nav1rad = getprop("instrumentation/nav[1]/radials/selected-deg");
            
            print("VOR1"~nav0freq);
            
            setprop("instrumentation/nav[0]/frequencies/selected-mhz",nav1freq);
            setprop("instrumentation/nav[0]/radials/selected-deg",nav1rad);
            setprop("instrumentation/nav[1]/frequencies/selected-mhz",nav0freq);
            setprop("instrumentation/nav[1]/radials/selected-deg",nav0rad);
          }
        }
        if (v == "LSK6L"){
          if (cduDisplay == "INIT_REF"){
            cduDisplay = "APP_REF";
          }
          if (cduDisplay == "APP_REF"){
            cduDisplay = "INIT_REF";
          }
          if ((cduDisplay == "IDENT") or (cduDisplay = "MAINT") or (cduDisplay = "PERF_INIT") or (cduDisplay = "POS_INIT") or (cduDisplay = "POS_REF") or (cduDisplay = "THR_LIM") or (cduDisplay = "TO_REF")){
            cduDisplay = "INIT_REF";
          }
        }
        if (v == "LSK6R"){
          if (cduDisplay == "THR_LIM"){
            cduDisplay = "TO_REF";
          }
          else if (cduDisplay == "APP_REF"){
            cduDisplay = "THR_LIM";
          }
          else if ((cduDisplay == "RTE1_1") or (cduDisplay == "RTE1_LEGS")){
            setprop("autopilot/route-manager/input","@ACTIVATE");
          }
          else if ((cduDisplay == "POS_INIT") or (cduDisplay == "DEP") or (cduDisplay == "RTE1_ARR") or (cduDisplay == "RTE1_DEP")){
            cduDisplay = "RTE1_1";
          }
          else if ((cduDisplay == "IDENT") or (cduDisplay == "TO_REF")){
            cduDisplay = "POS_INIT";
          }
          else if (cduDisplay == "EICAS_SYN"){
            cduDisplay = "EICAS_MODES";
          }
          else if (cduDisplay == "EICAS_MODES"){
            cduDisplay = "EICAS_SYN";
          }
          else if (cduDisplay == "INIT_REF"){
            cduDisplay = "MAINT";
          }
        }
        if (v == "EXEC"){
          if (cduDisplay == "RTE1_LEGS") {
            cduInput = cduSelectWaypoint(cduWpSelected, cduInput);
          }
        }
      }
			
			setprop("instrumentation/cdu/display",cduDisplay);
			if (eicasDisplay != nil){
				setprop("instrumentation/eicas/display",eicasDisplay);
			}
			setprop("instrumentation/cdu/input",cduInput);
		}
	}
	
var delete = func {
		var length = size(getprop("instrumentation/cdu/input")) - 1;
		setprop("instrumentation/cdu/input",substr(getprop("instrumentation/cdu/input"),0,length));
	}
	
var i = 0;

var plusminus = func {	
	var end = size(getprop("instrumentation/cdu/input"));
	var start = end - 1;
	var lastchar = substr(getprop("instrumentation/cdu/input"),start,end);
	if (lastchar == "+"){
		me.delete();
		me.input('-');
		}
	if (lastchar == "-"){
		me.delete();
		me.input('+');
		}
	if ((lastchar != "-") and (lastchar != "+")){
		me.input('+');
		}
	}

var cdu = func{
		var display = getprop("instrumentation/cdu/display");
		var serviceable = getprop("instrumentation/cdu/serviceable");
    var output = {
      title : "",
      page : "",
      leftTitle : [ "", "", "", "", "", "" ],
      left : [ "", "", "", "", "", "" ],
      centerTitle : [ "", "", "", "", "", "" ],
      center : [ "", "", "", "", "", "" ],
      rightTitle : [ "", "", "", "", "", "" ],
      right : [ "", "", "", "", "", "" ],
    };
		output.right[0] = "";	output.right[1] = "";	output.right[2] = "";	output.right[3] = "";	output.right[4] = "";	output.right[5] = "";
		
		if (display == "MENU") {
			output.title = "MENU";
			output.left[0] = "<FMC";
			output.rightTitle[0] = "EFIS CP";
			output.right[0] = "SELECT>";
			output.left[1] = "<ACARS";
			output.rightTitle[1] = "EICAS CP";
			output.right[1] = "SELECT>";
			output.left[5] = "<ACMS";
			output.right[5] = "CMC>";
		}
		if (display == "ALTN_NAV_RAD") {
			output.title = "ALTN NAV RADIO";
		}
		if (display == "APP_REF") {
			output.title = "APPROACH REF";
			output.leftTitle[0] = "GROSS WT";
			output.rightTitle[0] = "FLAPS    VREF";
			if (getprop("instrumentation/fmc/vspeeds/Vref") != nil){
				output.left[0] = getprop("instrumentation/fmc/vspeeds/Vref");
			}
			if (getprop("autopilot/route-manager/destination/airport") != nil){
				output.leftTitle[3] = getprop("autopilot/route-manager/destination/airport");
			}
			output.left[5] = "<INDEX";
			output.right[5] = "THRUST LIM>";
		}
		if (display == "DEP_ARR_INDEX") {
			output.title = "DEP/ARR INDEX";
			output.left[0] = "<DEP";
			output.centerTitle[0] = "RTE 1";
			if (getprop("autopilot/route-manager/departure/airport") != nil){
				output.center[0] = getprop("autopilot/route-manager/departure/airport");
			}
			output.right[0] = "ARR>";
			if (getprop("autopilot/route-manager/destination/airport") != nil){
				output.center[1] = getprop("autopilot/route-manager/destination/airport");
			}
			output.right[1] = "ARR>";
			output.left[2] = "<DEP";
			output.right[2] = "ARR>";
			output.right[3] = "ARR>";
			output.leftTitle[5] ="DEP";
			output.left[5] = "<----";
			output.center[5] = "OTHER";
			output.rightTitle[5] ="ARR";
			output.right[5] = "---->";
		}
		if (display == "EICAS_MODES") {
			output.title = "EICAS MODES";
			output.left[0] = "<ENG";
			output.right[0] = "FUEL>";
			output.left[1] = "<STAT";
			output.right[1] = "GEAR>";
			output.left[4] = "<CANC";
			output.right[4] = "RCL>";
			output.right[5] = "SYNOPTICS>";
		}
		if (display == "EICAS_SYN") {
			output.title = "EICAS SYNOPTICS";
			output.left[0] = "<ELEC";
			output.right[0] = "HYD>";
			output.left[1] = "<ECS";
			output.right[1] = "DOORS>";
			output.left[4] = "<CANC";
			output.right[4] = "RCL>";
			output.right[5] = "MODES>";
		}
		if (display == "FIX_INFO") {
			output.title = "FIX INFO";
			output.left[0] = sprintf("%3.2f", getprop("instrumentation/nav[0]/frequencies/selected-mhz-fmt"));
			output.right[0] = sprintf("%3.2f", getprop("instrumentation/nav[1]/frequencies/selected-mhz-fmt"));
			output.left[1] = sprintf("%3.2f", getprop("instrumentation/nav[0]/radials/selected-deg"));
			output.right[1] = sprintf("%3.2f", getprop("instrumentation/nav[1]/radials/selected-deg"));
			output.left[5] = "<ERASE FIX";
		}
		if (display == "IDENT") {
			output.title = "IDENT";
			output.leftTitle[0] = "MODEL";
			if (getprop("instrumentation/cdu/ident/model") != nil){
				output.left[0] = getprop("instrumentation/cdu/ident/model");
			}
			output.rightTitle[0] = "ENGINES";
			output.leftTitle[1] = "NAV DATA";
			if (getprop("instrumentation/cdu/ident/engines") != nil){
				output.right[0] = getprop("instrumentation/cdu/ident/engines");
			}
			output.left[5] = "<INDEX";
			output.right[5] = "POS INIT>";
		}
		if (display == "INIT_REF") {
			output.title = "INIT/REF INDEX";
			output.left[0] = "<IDENT";
			output.right[0] = "NAV DATA>";
			output.left[1] = "<POS";
			output.left[2] = "<PERF";
			output.left[3] = "<THRUST LIM";
			output.left[4] = "<TAKEOFF";
			output.left[5] = "<APPROACH";
			output.right[5] = "MAINT>";
		}
		if (display == "MAINT") {
			output.title = "MAINTENANCE INDEX";
			output.left[0] = "<CROS LOAD";
			output.right[0] = "BITE>";
			output.left[1] = "<PERF FACTORS";
			output.left[2] = "<IRS MONITOR";
			output.left[5] = "<INDEX";
		}
		if (display == "NAV_RAD") {
			output.title = "NAV RADIO";
			output.leftTitle[0] = "VOR L";
			output.left[0] = sprintf("%3.2f", getprop("instrumentation/nav[0]/frequencies/selected-mhz-fmt"));
			output.rightTitle[0] = "VOR R";
			output.right[0] = sprintf("%3.2f", getprop("instrumentation/nav[1]/frequencies/selected-mhz-fmt"));
			output.leftTitle[1] = "CRS";
			output.centerTitle[1] = "RADIAL";
			output.center[1] = sprintf("%3.2f", getprop("instrumentation/nav[0]/radials/selected-deg"))~"   "~sprintf("%3.2f", getprop("instrumentation/nav[1]/radials/selected-deg"));
			output.rightTitle[1] = "CRS";
			output.leftTitle[2] = "ADF L";
			output.left[2] = sprintf("%3.2f", getprop("instrumentation/adf[0]/frequencies/selected-khz"));
			output.rightTitle[2] = "ADF R";
			output.right[2] = sprintf("%3.2f", getprop("instrumentation/adf[1]/frequencies/selected-khz"));
      output.right[4] = "SWITCH>";
		}
		if (display == "PERF_INIT") {
			output.title = "PERF INIT";
			output.leftTitle[0] = "GR WT";
			output.rightTitle[0] = "CRZ ALT";
			output.right[0] = getprop("autopilot/route-manager/cruise/altitude-ft");
			output.leftTitle[1] = "FUEL";
			output.leftTitle[2] = "ZFW";
			output.leftTitle[3] = "RESERVES";
			output.rightTitle[3] = "CRZ CG";
			output.leftTitle[4] = "COST INDEX";
			output.rightTitle[4] = "STEP SIZE";
			output.left[5] = "<INDEX";
			output.right[5] = "THRUST LIM>";	
			if (getprop("sim/flight-model") == "jsb") {
				output.left[0] = sprintf("%3.1f", (getprop("fdm/jsbsim/inertia/weight-lbs")/1000));
				output.left[1] = sprintf("%3.1f", (getprop("fdm/jsbsim/propulsion/total-fuel-lbs")/1000));
				output.left[2] = sprintf("%3.1f", (getprop("fdm/jsbsim/inertia/empty-weight-lbs")/1000));
			}
			elsif (getprop("sim/flight-model") == "yasim") {
				output.left[0] = sprintf("%3.1f", (getprop("yasim/gross-weight-lbs")/1000));
				output.left[1] = sprintf("%3.1f", (getprop("consumables/fuel/total-fuel-lbs")/1000));

				yasim_emptyweight = getprop("yasim/gross-weight-lbs");
				yasim_emptyweight -= getprop("consumables/fuel/total-fuel-lbs");
				yasim_weights = props.globals.getNode("sim").getChildren("weight");
				for (i = 0; i < size(yasim_weights); i += 1) {
					yasim_emptyweight -= yasim_weights[i].getChild("weight-lb").getValue();
				}

				output.left[2] = sprintf("%3.1f", yasim_emptyweight/1000);
			}
		}
		if (display == "POS_INIT") {
			output.title = "POS INIT";
			output.left[5] = "<INDEX";
			output.right[5] = "ROUTE>";
		}
		if (display == "POS_REF") {
			output.title = "POS REF";
			output.leftTitle[0] = "FMC POST";
			output.left[0] = getprop("position/latitude-string")~" "~getprop("position/longitude-string");
			output.rightTitle[0] = "GS";
			output.right[0] = sprintf("%3.0f", getprop("velocities/groundspeed-kt"));
			output.left[4] = "<PURGE";
			output.right[4] = "INHIBIT>";
			output.left[5] = "<INDEX";
			output.right[5] = "BRG/DIST>";
		}
		if (display == "RTE1_1") {
			output.title = "RTE 1";
			output.page = "1/2";
			output.leftTitle[0] = "ORIGIN";
			if (getprop("autopilot/route-manager/departure/airport") != nil){
				output.left[0] = getprop("autopilot/route-manager/departure/airport");
			}
			output.rightTitle[0] = "DEST";
			if (getprop("autopilot/route-manager/destination/airport") != nil){
				output.right[0] = getprop("autopilot/route-manager/destination/airport");
			}
			output.leftTitle[1] = "RUNWAY";
			if (getprop("autopilot/route-manager/departure/runway") != nil){
				output.left[1] = getprop("autopilot/route-manager/departure/runway");
			}
			output.rightTitle[1] = "FLT NO";
			output.rightTitle[2] = "CO ROUTE";
			output.left[4] = "<RTE COPY";
			output.left[5] = "<RTE 2";
			if (getprop("autopilot/route-manager/active") == 1){
				output.right[5] = "PERF INIT>";
				}
			else {
				output.right[5] = "ACTIVATE>";
				}
		}
		if (display == "RTE1_2") {
			output.title = "RTE 1";
			output.page = "2/2";
			output.leftTitle[0] = "VIA";
			output.rightTitle[0] = "TO";
			if (getprop("autopilot/route-manager/route/wp[1]/id") != nil){
				output.right[0] = getprop("autopilot/route-manager/route/wp[1]/id");
				}
			if (getprop("autopilot/route-manager/route/wp[2]/id") != nil){
				output.right[1] = getprop("autopilot/route-manager/route/wp[2]/id");
				}
			if (getprop("autopilot/route-manager/route/wp[3]/id") != nil){
				output.right[2] = getprop("autopilot/route-manager/route/wp[3]/id");
				}
			if (getprop("autopilot/route-manager/route/wp[4]/id") != nil){
				output.right[3] = getprop("autopilot/route-manager/route/wp[4]/id");
				}
			if (getprop("autopilot/route-manager/route/wp[5]/id") != nil){
				output.right[4] = getprop("autopilot/route-manager/route/wp[5]/id");
				}
			output.left[5] = "<RTE 2";
			output.right[5] = "ACTIVATE>";
		}
		if (display == "RTE1_ARR") {
			if (getprop("autopilot/route-manager/destination/airport") != nil){
				output.title = getprop("autopilot/route-manager/destination/airport")~" ARRIVALS";
			}
			else{
				output.title = "ARRIVALS";
			}
			output.leftTitle[0] = "STARS";
			output.rightTitle[0] = "APPROACHES";
			if (getprop("autopilot/route-manager/destination/runway") != nil){
				output.right[0] = getprop("autopilot/route-manager/destination/runway");
			}
			output.leftTitle[1] = "TRANS";
			output.rightTitle[2] = "RUNWAYS";
			output.left[5] = "<INDEX";
			output.right[5] = "ROUTE>";
		}
		if (display == "RTE1_DEP") {
			if (getprop("autopilot/route-manager/departure/airport") != nil){
				output.title = getprop("autopilot/route-manager/departure/airport")~" DEPARTURES";
			}
			else{
				output.title = "DEPARTURES";
			}
			output.leftTitle[0] = "SIDS";
			output.rightTitle[0] = "RUNWAYS";
			if (getprop("autopilot/route-manager/departure/runway") != nil){
				output.right[0] = getprop("autopilot/route-manager/departure/runway");
			}
			output.leftTitle[1] = "TRANS";
			output.left[5] = "<ERASE";
			output.right[5] = "ROUTE>";
		}
		if (display == "RTE1_LEGS") {
			if (getprop("autopilot/route-manager/active") == 1){
				output.title = "ACT RTE 1 LEGS";
				}
			else {
				output.title = "RTE 1 LEGS";
				}
        
      var activeWp = int(getprop("autopilot/route-manager/current-wp"));
      if (activeWp>0) {
        if (activeWp - cduWpOffset == 1) output.center[0] = "<-- ACTIVE";
        if (activeWp - cduWpOffset == 2) output.center[1] = "<-- ACTIVE";
        if (activeWp - cduWpOffset == 3) output.center[2] = "<-- ACTIVE";
        if (activeWp - cduWpOffset == 4) output.center[3] = "<-- ACTIVE";
        if (activeWp - cduWpOffset == 5) output.center[4] = "<-- ACTIVE";
      }
      
      var formatAltitude = func(lineIndex) {
        var alt = getprop("autopilot/route-manager/route/wp["~(cduWpOffset+lineIndex)~"]/altitude-ft");
        if (alt >= 0) {
          return sprintf("%5.0f", alt);
        } else {
          return "-----";
        }
      };
      
			if (getprop("autopilot/route-manager/route/wp["~(cduWpOffset+1)~"]/id") != nil){
				output.leftTitle[0] = sprintf("%3.0f", getprop("autopilot/route-manager/route/wp["~(cduWpOffset+1)~"]/leg-bearing-true-deg"));
				output.left[0] = getprop("autopilot/route-manager/route/wp["~(cduWpOffset+1)~"]/id");
				output.centerTitle[1] = sprintf("%3.0f", getprop("autopilot/route-manager/route/wp["~(cduWpOffset+1)~"]/leg-distance-nm"))~" NM";
				output.right[0] = formatAltitude(1);
				if (getprop("autopilot/route-manager/route/wp["~(cduWpOffset+1)~"]/speed-kts") != nil){
					output.right[3] = getprop("autopilot/route-manager/route/wp["~(cduWpOffset+1)~"]/speed-kts")~"/"~sprintf("%5.0f", getprop("autopilot/route-manager/route/wp["~(cduWpOffset+1)~"]/altitude-ft"));
					}
				}
			if (getprop("autopilot/route-manager/route/wp["~(cduWpOffset+2)~"]/id") != nil){
				if (getprop("autopilot/route-manager/route/wp["~(cduWpOffset+2)~"]/leg-bearing-true-deg") != nil){
					output.leftTitle[1] = sprintf("%3.0f", getprop("autopilot/route-manager/route/wp["~(cduWpOffset+2)~"]/leg-bearing-true-deg"));
				}
				output.left[1] = getprop("autopilot/route-manager/route/wp["~(cduWpOffset+2)~"]/id");
				if (getprop("autopilot/route-manager/route/wp["~(cduWpOffset+2)~"]/leg-distance-nm") != nil){
					output.centerTitle[2] = sprintf("%3.0f", getprop("autopilot/route-manager/route/wp["~(cduWpOffset+2)~"]/leg-distance-nm"))~" NM";
				}
				output.right[1] = formatAltitude(2);
				if (getprop("autopilot/route-manager/route/wp["~(cduWpOffset+2)~"]/speed-kts") != nil){
					output.right[3] = getprop("autopilot/route-manager/route/wp["~(cduWpOffset+2)~"]/speed-kts")~"/"~sprintf("%5.0f", getprop("autopilot/route-manager/route/wp["~(cduWpOffset+2)~"]/altitude-ft"));
					}
				}
			if (getprop("autopilot/route-manager/route/wp["~(cduWpOffset+3)~"]/id") != nil){
				if (getprop("autopilot/route-manager/route/wp["~(cduWpOffset+3)~"]/leg-bearing-true-deg") != nil){
					output.leftTitle[2] = sprintf("%3.0f", getprop("autopilot/route-manager/route/wp["~(cduWpOffset+3)~"]/leg-bearing-true-deg"));
				}
				output.left[2] = getprop("autopilot/route-manager/route/wp["~(cduWpOffset+3)~"]/id");
				if (getprop("autopilot/route-manager/route/wp["~(cduWpOffset+3)~"]/leg-distance-nm") != nil){
					output.centerTitle[3] = sprintf("%3.0f", getprop("autopilot/route-manager/route/wp["~(cduWpOffset+3)~"]/leg-distance-nm"))~" NM";
				}
				output.right[2] = formatAltitude(3);
				if (getprop("autopilot/route-manager/route/wp["~(cduWpOffset+3)~"]/speed-kts") != nil){
					output.right[2] = getprop("autopilot/route-manager/route/wp["~(cduWpOffset+3)~"]/speed-kts")~"/"~sprintf("%5.0f", getprop("autopilot/route-manager/route/wp["~(cduWpOffset+3)~"]/altitude-ft"));;
					}
				}
			if (getprop("autopilot/route-manager/route/wp["~(cduWpOffset+4)~"]/id") != nil){
				if (getprop("autopilot/route-manager/route/wp["~(cduWpOffset+4)~"]/leg-bearing-true-deg") != nil){
					output.leftTitle[3] = sprintf("%3.0f", getprop("autopilot/route-manager/route/wp["~(cduWpOffset+4)~"]/leg-bearing-true-deg"));
				}
				output.left[3] = getprop("autopilot/route-manager/route/wp["~(cduWpOffset+4)~"]/id");
				if (getprop("autopilot/route-manager/route/wp["~(cduWpOffset+4)~"]/leg-distance-nm") != nil){
					output.centerTitle[4] = sprintf("%3.0f", getprop("autopilot/route-manager/route/wp["~(cduWpOffset+4)~"]/leg-distance-nm"))~" NM";
				}
				output.right[3] = formatAltitude(4);
				if (getprop("autopilot/route-manager/route/wp["~(cduWpOffset+4)~"]/speed-kts") != nil){
					output.right[3] = getprop("autopilot/route-manager/route/wp["~(cduWpOffset+4)~"]/speed-kts")~"/"~sprintf("%5.0f", getprop("autopilot/route-manager/route/wp["~(cduWpOffset+4)~"]/altitude-ft"));
					}
				}
			if (getprop("autopilot/route-manager/route/wp["~(cduWpOffset+5)~"]/id") != nil){
				if (getprop("autopilot/route-manager/route/wp["~(cduWpOffset+5)~"]/leg-bearing-true-deg") != nil){
					output.leftTitle[4] = sprintf("%3.0f", getprop("autopilot/route-manager/route/wp["~(cduWpOffset+5)~"]/leg-bearing-true-deg"));
				}
				output.left[4] = getprop("autopilot/route-manager/route/wp["~(cduWpOffset+5)~"]/id");
				output.right[4] = formatAltitude(5);
				if (getprop("autopilot/route-manager/route/wp["~(cduWpOffset+5)~"]/speed-kts") != nil){
					output.right[3] = getprop("autopilot/route-manager/route/wp["~(cduWpOffset+5)~"]/speed-kts")~"/"~sprintf("%5.0f", getprop("autopilot/route-manager/route/wp["~(cduWpOffset+5)~"]/altitude-ft"));
					}
				}
			output.left[5] = "<RTE 2 LEGS";
			if (getprop("autopilot/route-manager/active") == 1){
				output.right[5] = "RTE DATA>";
				}
			else{
				output.right[5] = "ACTIVATE>";
				}
		}
		if (display == "THR_LIM") {
			output.title = "THRUST LIM";
			output.leftTitle[0] = "SEL";
			output.centerTitle[0] = "OAT";
			output.center[0] = sprintf("%2.0f", getprop("environment/temperature-degc"))~" °C";
			output.rightTitle[0] = "TO 1 N1";
			output.left[1] = "<TO";
			output.right[1] = "CLB>";
			output.leftTitle[2] = "TO 1";
			output.left[2] = "<-10%";
			output.center[2] = "<SEL> <ARM>";
			output.right[2] = "CLB 1>";
			output.leftTitle[3] = "TO 2";
			output.left[3] = "<-20%";
			output.right[3] = "CLB 2>";
			output.left[5] = "<INDEX";
			output.right[5] = "TAKEOFF>";
		}
		if (display == "TO_REF") {
			output.title = "TAKEOFF REF";
			output.leftTitle[0] = "FLAP/ACCEL HT";
			output.left[0] = sprintf("%2.0f", getprop("instrumentation/fmc/to-flap"));
			output.rightTitle[0] = "REF V1";
			if (getprop("instrumentation/fmc/vspeeds/V1") != nil){
				output.right[0] = sprintf("%3.0f", getprop("instrumentation/fmc/vspeeds/V1"));
			}
			output.leftTitle[1] = "E/O ACCEL HT";
			output.rightTitle[1] = "REF VR";
			if (getprop("instrumentation/fmc/vspeeds/VR") != nil){
				output.right[1] = sprintf("%3.0f", getprop("instrumentation/fmc/vspeeds/VR"));
			}
			output.leftTitle[2] = "THR REDUCTION";
			output.rightTitle[2] = "REF V2";
			if (getprop("instrumentation/fmc/vspeeds/V2") != nil){
				output.right[2] = sprintf("%3.0f", getprop("instrumentation/fmc/vspeeds/V2"));
			}
			output.leftTitle[3] = "WIND/SLOPE";
			output.rightTitle[3] = "TRIM   CG";
			output.rightTitle[4] = "POS SHIFT";
			output.left[5] = "<INDEX";
			output.right[5] = "POS INIT>";
		}
    if (display == "HOLD") {
      cduHold.render(output);
    }
		
		if (serviceable != 1){
			output.title = "";		output.page = "";
			output.title = "";
      output.page = "";
      output.leftTitle = [ "", "", "", "", "", "" ];
      output.left = [ "", "", "", "", "", "" ];
      output.centerTitle = [ "", "", "", "", "", "" ];
      output.center = [ "", "", "", "", "", "" ];
      output.rightTitle = [ "", "", "", "", "", "" ];
      output.right = [ "", "", "", "", "", "" ];
		}
		
		setprop("instrumentation/cdu/output/title",output.title);
		setprop("instrumentation/cdu/output/page",output.page);
    for (i = 0; i < 6;  i += 1) { 
		  setprop("instrumentation/cdu/output/line"~( i + 1 )~"/left-title",output.leftTitle[i]);
      setprop("instrumentation/cdu/output/line"~( i + 1 )~"/left",output.left[i]);
		  setprop("instrumentation/cdu/output/line"~( i + 1 )~"/center-title",output.centerTitle[i]);
      setprop("instrumentation/cdu/output/line"~( i + 1 )~"/center",output.center[i]);
		  setprop("instrumentation/cdu/output/line"~( i + 1 )~"/right-title",output.rightTitle[i]);
      setprop("instrumentation/cdu/output/line"~( i + 1 )~"/right",output.right[i]);
    }
		settimer(cdu,0.2);
    }
_setlistener("sim/signals/fdm-initialized", cdu); 
