(function () {
    // make this a Retina widget
    var widget = Retina.Widget.extend({
        about: {
            title: "KBase Data Importer",
            name: "kbupload",
	    version: 1,
            author: "Tobias Paczian",
	    // Requires are:
	    // AuxStore - SHOCK interface library
	    // Client.js - Workspace interface library
	    // xlsx - Excel parser / generator
	    // jszip - ZIP library required for Excel parser
            requires: [ 'AuxStore.js', 'Client.js', 'xlsx.js', 'jszip.min.js' ]
        }
    });

    // load required renderers, currently listselect only
    widget.setup = function () {
	return [ Retina.add_renderer({"name": "listselect", "resource": "renderers/",  "filename": "renderer.listselect.js" }),
		 Retina.load_renderer("listselect") ];
    }

    // global vars
    widget.auth = false;
    widget.user = null;
    widget.token = null;
    widget.currentFile = 0;
    widget.newWorkspaceName = "";
    widget.jsonTemplates = {};
    widget.templates = {};
    widget.validatedTemplates = {};
    widget.metaDataValidated = false;
    widget.allowedFileEndings = RetinaConfig.allowedFileEndings || [ "fna", "fas", "fasta", "sff", "fastq", "fq", "txt", "xlsx" ];

    // initial display
    widget.display = function (params) {
	var widget = Retina.WidgetInstances.kbupload[1];

	// set SHOCK url to data in config.js
	SHOCK.url = RetinaConfig.shock;

	// load all JSON template files defined in config.js
	widget.loadTemplates();

	// initialize a storage spot in the DataStore for the awe jobs
	stm.DataStore.awejobs = {};

	// set the target DOM element from the params
	var target = params.target;

	// introductory text, always displayed
	var introSection = "<h4>Overview</h4><p style='margin-top: 10px;'>The KBase Data Importer allows the creation of KBase typed objects for further analysis. The process of creating a typed object typically involves adding data about the data (metadata). We support a number of community standards to import metadata. If metadata is required for your chosen data type, you can download an Excel spreadsheet by clicking the <b>download Excel template</b> button in step 2. Once you have filled out the spreadsheet and have uploaded it to the staging area (step 1), it will become available for selection in step 2.</p>\
<p>The typed objects will be placed in a workspace of your choice.</p>\
<p>Please note the you will not be able to download data uploaded to KBase until it is validated and processed. Finally you can proceed with the creation of a typed Workspace object.</p>";

	// text displayed when no user is logged in
	var unauthorized = "<legend>Login required</legend><p>You must log in at the top right of the screen before you can use the data uploader.</p>";
		
	// put intro html into the target DOM element
	target.innerHTML = introSection + "<div id='unauthorized_section'>"+unauthorized + "</div><div id='authorized_section' class='blocks' style='display: none;'><div id='templateSection'></div><div id='uploadSection'></div><div id='inboxSection'></div><div id='submissionSection'></div><div id='pipelineSection'></div></div>";

	// initialize the staging area
	widget.inboxDisplay(document.getElementById('inboxSection'));
    };

    /*
     * DISPLAYS
     */

    // staging area
    widget.inboxDisplay = function (target) {
	var widget = Retina.WidgetInstances.kbupload[1];

	// create a div for the intro HTML
	var intro = document.createElement('div');
	var html = '<legend>Step 1: Manage Staging Files</legend>';
	intro.innerHTML = html;
	target.appendChild(intro);

	// create the progress display and make it invisible
	var progress = document.createElement('div');
	progress.setAttribute('class', "alert alert-block alert-info");
	progress.setAttribute('style', "width: 400px; display: none; z-index: 100000");
	progress.innerHTML = "<p>initializing upload...</p>";
	widget.progress = progress;
	target.appendChild(progress);
	
	// create a file dialog
	var fu = document.createElement('div');
	target.appendChild(fu);
	
	// hide the original button
	var fuDialog = widget.fu = document.createElement('input');
	fuDialog.setAttribute('type', 'file');
	fuDialog.setAttribute('style', 'display:none;');
	fuDialog.setAttribute('multiple', 'multiple');

	// handle the change event
	fuDialog.addEventListener('change', function(event){
	    var widget = Retina.WidgetInstances.kbupload[1];

	    // reset the current file index
	    widget.currentFile = 0;
	    widget.processFileUpload();
	    
	});
	fu.appendChild(fuDialog);
	
	// create a fake button that clicks the real button when pressed
	// this is because the styles of the original button cannot be modified
	// due to browser security restrictions
	var fakeButton = document.createElement('button');
	fakeButton.setAttribute('class', 'btn');
	fakeButton.innerHTML = "upload file to stage";
	fakeButton.addEventListener('click', function() {
	    fuDialog.click();
	});
	fu.appendChild(fakeButton);
	fu.setAttribute('style', "margin-bottom: 25px;");
	
	// create a select box that holds the files within the staging area
	// the onChange event will trigger the showFileOptions function, so the
	// file information and action buttons can be displayed
	// the select box is initially empty and filled by the updateInbox function
	var inb = document.createElement('div');
	var result = '<div><select id="shock_result" multiple size=10 onchange="Retina.WidgetInstances.kbupload[1].showFileOptions(this.options[this.selectedIndex].value);" style="width: 400px;"></select><div id="fileOptions" style="float: right;width: 500px;"></div></div>';
	inb.innerHTML = result;
	target.appendChild(inb);
    };

    widget.processFileUpload = function () {
	var widget = Retina.WidgetInstances.kbupload[1];

	if (widget.fu.files.length > widget.currentFile) {

	    // get the selected file name and make sure it matches one of the allowed file endings
	    var fn = widget.fu.files[widget.currentFile].name;
	    var allowed = false;
	    for (var i=0;i<widget.allowedFileEndings.length; i++) {
		if (fn.match(new RegExp("\."+widget.allowedFileEndings[i]+"$"))) {
		    allowed = true;
		    break;
		}
	    }
	    
	    // if the file type is allowed, commence the upload
	    if (allowed) {
		var progress = widget.progress;
		progress.style.display = "";
		progress.innerHTML = "";
		var closeButton = document.createElement('button');
		closeButton.setAttribute('class', 'close');
		closeButton.setAttribute('type', 'button');
		closeButton.setAttribute('data-dismiss', 'alert');
		progress.appendChild(closeButton);
		var fileName = document.createElement('p');
		fileName.innerHTML = 'uploading '+widget.fu.files[widget.currentFile].name + (widget.fu.files.length > 1 ? " (file "+(widget.currentFile + 1)+" of "+widget.fu.files.length+")" : "");
		progress.appendChild(fileName);
		var progressBox = document.createElement('p');
		progressBox.setAttribute('style', 'margin-bottom: 5px;');
		widget.progressCurrent = document.createElement('span');
		widget.progressCurrent.innerHTML = 0;
		progressBox.appendChild(widget.progressCurrent);
		var progressTotal = document.createElement('span');
		progressTotal.innerHTML = ' of '+stm.prettySize(widget.fu.files[widget.currentFile].size)+' complete';
		progressBox.appendChild(progressTotal);
		progress.appendChild(progressBox);
		var pBar = document.createElement('div');
		pBar.setAttribute('class', 'progress');
		widget.pBarInner = document.createElement('div');
		widget.pBarInner.setAttribute('class', 'bar');
		widget.pBarInner.setAttribute('style', 'width: 0%;');
		pBar.appendChild(widget.pBarInner);
		progress.appendChild(pBar);
		
		// issue the SHOCK upload command on this file upload dialog, set the progress function callback
		// to onProgress and the completion callback to uploadComplete (both functions within this widget
		SHOCK.upload(widget.fu, null, null, widget.uploadComplete,widget.onProgress, widget.currentFile).then( function() {
		    var widget = Retina.WidgetInstances.kbupload[1];
		    widget.progress.style.display = "none";
		    widget.currentFile++;
		    widget.processFileUpload();
		});
	    } else {
		
		// inform the user that the selected filetype is not allowed
		alert("The selected filetype of file '"+fn+"' is not allowed.\nValid filetypes are:\n*."+Retina.WidgetInstances.kbupload[1].allowedFileEndings.join(", *."));
		widget.currentFile++;
		widget.processFileUpload();
	    }
	}
    };

    // the submission area
    widget.submissionDisplay = function (target) {
	var widget = Retina.WidgetInstances.kbupload[1];

	// the intro div holds the pipeline selection
	// currently its contents are hardcoded, in future this will be filled from the
	// pipeline structure files
	// the onChange event triggers the showSubtype function which will change the input mask for the user.
	// currently this only changes the text, in future this will also change the input elements
	var intro = document.createElement('div');
	var html = '\
<legend>Step 2: Perform Submission</legend>\
<p style="float: left; padding-top: 5px; margin-right: 10px;">select type</p>\
<select id="subtype" name="subtype" onchange="Retina.WidgetInstances.kbupload[1].showSubtype(this);" style="float: left;">';
	for (var i in widget.templates) {
	    if (widget.templates.hasOwnProperty(i)) {
		html += '<option selected value="TestData">'+i+'</option>';
	    }
	}
	var others = [ "amplicon data set",
		       "metatranscriptome",
		       "re-sequencing",
		       "rna-seq transcriptome",
		       "GWAS",
		       "PPI Network",
		       "co expression network",
		       "co fitness",
		       "metabolic subsystem",
		       "multidata int network",
		       "other network" ];

	for (var i=0; i<others.length; i++) {
	    if (! widget.templates.hasOwnProperty(others[i])) {
		html += '<option selected value="TestData">'+others[i]+'</option>';
	    }
	}

	html += '</select>\
<div id="subtype_description" style="margin-left: 20px; width: 700px;clear: both;"></div>\
<div class="alert alert-info" style="margin-top: 20px;width: 562px; margin-left: 20px;">\
<b>Note: </b>\
The time between submission and a resulting data object in the workspace may take some time depending on the selected pipeline. In some cases, like the Microbial Communities pipeline, this might be several days.\
</div>';

	intro.innerHTML = html;
	target.appendChild(intro);

	// select the first entry
	var sel = document.getElementById('subtype');
	sel.selectedIndex = 0;

	// the input mask for the selected pipeline is rendered in this function
	widget.showSubtype(sel);
    };

    /*
     * SHOWS
     */

    // render the intro text for the currently selected pipeline
    // currently only renders the intro text and the data is hardcoded here
    // in future this data will be loaded from the pipeline structure files and include
    // the input elements
    widget.showSubtype = function (sel) {
	var widget = Retina.WidgetInstances.kbupload[1];

	// get the target DOM element
	var result = document.getElementById('subtype_description');

	// store potential list selects
	var listSelects = widget.listSelects = {};
	Retina.RendererInstances.listselect = [ Retina.RendererInstances.listselect[0] ];

	// initialize the html in case there is no template
	var html = "<table style='margin-bottom: 5px;'><tr><td class='section'><h4>Not Implemented</h4><p>This submission type has not yet been implemented.</p></td></tr></table>";
	var templateName = sel.options[sel.selectedIndex].text;

	// remove the previous metadata validations
	widget.validatedTemplates = {};
	widget.metaDataValidated = false;
	widget.jsonTemplates = {};

	// recompute all metadata files agains the current template
	if (widget.templates.hasOwnProperty(templateName) && widget.templates[templateName].hasOwnProperty('metadata')) {
	    for (var i in stm.DataStore.inbox) {
		if (stm.DataStore.inbox.hasOwnProperty(i)) {
		    var data = stm.DataStore.inbox[i];
		    if (data.attributes.hasOwnProperty('name') && data.attributes.name.match(/\.xlsx$/)) {
			widget.excelToJSON(i);
		    }
		}
	    }
	}

	// if there is a template, use it to fill the html
	if (widget.templates.hasOwnProperty(templateName)) {

	    // get the interface part of the template
	    var iT = widget.templates[templateName]["interface"];

	    // set title and text
	    html = "<table style='margin-bottom: 5px;'><tr><td class='section'><h4>"+iT.intro.title+"</h4><p>"+iT.intro.text+"</p></td>";

	    // add metadata buttons if requested
	    if (iT.intro.excel || iT.intro.json) {
		html += "<td style='width: 200px;'>";
		if (iT.intro.json) {
		    html += "<button class='btn' style='width: 190px; margin-bottom: 5px;' onclick='Retina.WidgetInstances.kbupload[1].jsonTemplate(\"" + templateName + "\");'>download JSON template</button>";
		}
		if (iT.intro.json && iT.intro.excel) {
		    html += "<br>";
		}
		if (iT.intro.excel) {
		    html += "<button class='btn' style='width: 190px; margin-bottom: 5px;' onclick='Retina.WidgetInstances.kbupload[1].xlsInit(\"" + templateName + "\");'>download Excel template</button>";
		}
		html += "</td>";
	    }

	    // close the info section, start the input section
	    html += '</tr><tr><td colspan=2><h4>required data</h4></td></tr></table><div><fieldset><label>select target workspace</label>\
    <select id="workspaceSelector"></select>\
    <div id="newWorkspaceName" style="display: none;">\
      <p>new workspace name</p>\
      <div class="input-append">\
        <input type="text" id="newWorkspaceNameField" onkeypress="if(event.keyCode==\'13\'){this.nextSibling.click();}">\
        <button class="btn" onclick="Retina.WidgetInstances.kbupload[1].createNewWorkspace();">create</button>\
      </div>\
    </div>\
';

	    // iterate over the inputs
	    for (var i=0; i<iT.inputs.length; i++) {
		if (iT.inputs[i].type == "text") {
		    html += "<label>"+iT.inputs[i].label +"</label>";
		    html += "<input type='text' id='submissionField"+iT.inputs[i].aweVariable+"' value='"+iT.inputs[i]["default"]+"'>";
		} else if(iT.inputs[i].type == "checkbox") {
		    html += "<label class='checkbox'>";
		    var checked = "";
		    if (iT.inputs[i]["default"]) {
			checked = "checked ";
		    }
		    html += '<input type="checkbox" '+checked+'id="submissionField'+iT.inputs[i].aweVariable+'"> '+iT.inputs[i].label;
		    html += '</label>';
		} else if (iT.inputs[i].type == "multiselect") {
		    listSelects[i] = Retina.Renderer.create("listselect", { multiple: true,
									    no_button: true,
									    value: "id",
									    filter: ["name"],
									    no_filter: true,
									    select_id: "submissionField"+iT.inputs[i].aweVariable });
		    html += "<div id='submissionFieldDiv"+iT.inputs[i].aweVariable+"'>";
		} else if (iT.inputs[i].type == "radio") {
		    html += "<label>"+iT.inputs[i].label +"</label>";
		    for (var h=0; h<iT.inputs[i].data.length; h++) {
			var checked = "";
			if (h == iT.inputs[i]["default"]) {
			    checked = "checked ";
			}
			html += "<input type='radio' "+checked+"name='submissionField"+iT.inputs[i].aweVariable+"' value='"+iT.inputs[i].data[h].value+"'>";
		    }
		} else if (iT.inputs[i].type == "dropdown") {
		    var metaDataChange = "";
		    var button = "";
		    if (iT.inputs[i].isMetadata) {
			button = "<div class='input-append'>";
			metaDataChange = ' onchange="Retina.WidgetInstances.kbupload[1].metaDataValidated=false;document.getElementById(\'metadataValidationDiv\').className=\'alert\';document.getElementById(\'metadataValidationDiv\').innerHTML=\'validation required\';"';
		    }
		    html += "<label>"+iT.inputs[i].label +'</label>'+button+'<select id="submissionField'+iT.inputs[i].aweVariable+'"'+metaDataChange+'>';
		    if (iT.inputs[i].data) {
			for (var h=0; h<iT.inputs[i].data.length; h++) {
			    var selected = "";
			    if (iT.inputs[i].data[h].label == iT.inputs[i]["default"]) {
				selected = "selected ";
			    }
			    html += "<option "+selected+" value='"+iT.inputs[i].data[h].value+"'>"+iT.inputs[i].data[h].label+"</option>";
			}
		    }
		    html += "</select>";
		    if (iT.inputs[i].isMetadata) {
			html += '<button class="btn" onclick="Retina.WidgetInstances.kbupload[1].validateMetadata(document.getElementById(\'submissionField'+iT.inputs[i].aweVariable+'\'));">validate <b>'+templateName+'</b> metadata</button></div><div id="metadataValidationDiv" class="alert" style="width: 562px;">validation required</div>';
		    }
		}

		if (iT.inputs[i].help) {
		    html += "<span class='help-block'>"+iT.inputs[i].help+"</span>";
		}
	    }

	    html += '</fieldset><button type="submit" id="aweSubmitButton" class="btn" onclick="Retina.WidgetInstances.kbupload[1].validateSlots();" style="margin-top: 10px;">submit</button></div>';
	}

	// set the content of the target DOM element to the generated HTML
	result.innerHTML = html;

	// call the function to update fields fed by files
	widget.updateFileFields();
	if (document.getElementById('workspaceSelector')) {
	    widget.getWorkspaces(1);
	}
    };

    // retrieves the staging area files for the current user from SHOCK
    widget.showShockResult = function (data) {
	var widget = Retina.WidgetInstances.kbupload[1];

	// hashify the array result so we can better store it in the DataStore
	var dataHash = {};
	
	// store staging area files
	var selectOptions = "";

	// iterate over the result data
	for (var i=0;i<data.length;i++) {
	    // store every file data in DataStore
	    dataHash[data[i].id] = data[i];

	    // create an option for the staging file box
	    if(data[i].attributes.hasOwnProperty('name')) {
		if (data[i].attributes.name.match(/\.xlsx$/)) {
		    widget.excelToJSON(data[i].id);
		}
		selectOptions += "<option value='"+data[i].id+"'>"+data[i].attributes.name+"</option>";
	    }
	}

	// store the file data in the DataStore
	stm.DataStore.inbox = dataHash;

	// fill the staging area select box
	document.getElementById('shock_result').innerHTML = selectOptions;
	
	// update all file fields
	widget.updateFileFields();
    };

    // retrieves the pipeline stati for the current user from AWE
    widget.showAWEResult = function (data) {
	var widget = Retina.WidgetInstances.kbupload[1];

	if (! data) {
	    // get the pipeline status information from AWE and call the showAWEResult function
	    jQuery.ajax(RetinaConfig.awe.url+"/job?query&info.user="+widget.user+"&info.project=data-importer", 
			{ 
			    success: function (data) {
				Retina.WidgetInstances.kbupload[1].showAWEResult(data);
			    },
			    headers: { "Authorization": "OAuth "+Retina.WidgetInstances.kbupload[1].token,
				       "Datatoken": Retina.WidgetInstances.kbupload[1].token }
			});
	    return;
	}

	var target = document.getElementById('pipelineSection');

	var html = "<legend>Submission Status<button title='refresh' class='btn btn-mini pull-right' onclick='Retina.WidgetInstances.kbupload[1].showAWEResult();'><i class='icon icon-refresh'></i></button></legend>";
	
	var subs = [];
	for (var i=0;i<data.data.length;i++) {
	    var item = data.data[i];
	    if (item.remaintasks > 0) {
		if (item.state != "deleted") {
		    var currtask = item.tasks[item.tasks.length - item.remaintasks];
		    var numtasks = item.tasks.length;
		    if (item.hasOwnProperty('lastfailed') && item.lastfailed.length) {
			jQuery.ajax(RetinaConfig.awe.url+"/work/"+item.lastfailed+"?report=stderr", 
			{ 
			    success: function (data) {
				console.log(data.data);
			    },
			    headers: { "Authorization": "OAuth "+Retina.WidgetInstances.kbupload[1].token }
			});
		    }
		    subs.push([ item.info.name, Retina.WidgetInstances.kbupload[1].dots(item.tasks), item.info.submittime, "-", "<button type='button' class='btn btn-mini btn-danger' onclick='if(confirm(\"Really delete this job? This cannot be undone!\")){Retina.WidgetInstances.kbupload[1].deleteJob(this, \""+item.id+"\");}'>delete</button>"]);
		}
	    } else {
		var laststate = item.tasks[item.tasks.length - 1].state;
		if (item.state != "deleted" && laststate != "deleted") {
		    subs.push([ item.info.name, Retina.WidgetInstances.kbupload[1].dots(item.tasks), item.info.submittime, (laststate == "completed") ? item.info.completedtime : "-", "<button type='button' class='btn btn-mini btn-danger' onclick='if(confirm(\"Really delete this job? This cannot be undone!\")){Retina.WidgetInstances.kbupload[1].deleteJob(this, \""+item.id+"\");}'>delete</button>"]);
		}
	    }
	}
	if (subs.length) {
	    var columns = ["submission type", "status", "submission time", "completion time", "delete"];
	    html += "<table class='table table-hover'>";
	    html += "<thead><tr><th>"+columns.join("</th><th>")+"</th></tr></thead><tbody>";
	    for (var i=0;i<subs.length;i++) {
		html += "<tr><td>"+subs[i].join("</td><td>")+"</td></tr>";
	    }
	    html += "</tbody></table>";
	} else {
	    html += "<p>You currently have no running submissions.</p>";
	}

	target.innerHTML = html;
    };

    // delete an AWE job
    widget.deleteJob = function(button, id) {
	var widget = Retina.WidgetInstances.kbupload[1];

	button.parentNode.parentNode.parentNode.removeChild(button.parentNode.parentNode);
	
	jQuery.ajax(RetinaConfig.awe.url+"/job/"+id, { headers: { "Authorization": "OAuth "+Retina.WidgetInstances.kbupload[1].token,
								  "Datatoken": Retina.WidgetInstances.kbupload[1].token },
						       method: "DELETE" });
    };

    // show additional information and action buttons for a selected file
    // this is issued by a click in the staging area select box
    widget.showFileOptions = function (id) {
	var widget = Retina.WidgetInstances.kbupload[1];

	// get the file information from the DataStore
	var dataItem = stm.DataStore.inbox[id];

	// get the DOM element to hold the file options
	var fo = document.getElementById('fileOptions');

	// create the html to be filled into the file options DOM element
	var html = "";

	// generic file information
	var info = "<table><tr><td><strong>filename</strong></td><td>"+dataItem.attributes.name+"</td></tr>\
<tr><td><strong>size</strong></td><td>"+stm.prettySize(dataItem.file.size)+"</td></tr>\
<tr><td><strong>upload time</strong></td><td>"+dataItem.created_on+"</td></tr>\
<tr><td><strong>md5</strong></td><td>"+dataItem.file.checksum.md5+"</td></tr>\
<tr><td><strong>id</strong></td><td>"+dataItem.id+"</td></tr>\
</table><br>";
	
	// active action buttons
	var deleteButton = "<button class='btn optionButton' onclick='if(confirm(\"Really delete this file?\")){SHOCK.delete_node(\""+id+"\").then(function(){ Retina.WidgetInstances.kbupload[1].updateInbox();});}'>delete</button>";

	// inactive action buttons, these still need implementation
	var translateIDsButton = "<button class='btn optionButton' disabled>translate IDs into KBase</button>";
	var joinPairedEndsButton = "<button class='btn optionButton' disabled>join paired ends</button>";
	var demultiplexButton = "<button class='btn optionButton' disabled>demultiplex</button>";

	var testButton = "<button class='btn optionButton' onclick='Retina.WidgetInstances.kbupload[1].test(\""+id+"\");'>test</button>";

	// currently all action buttons are always displayed. In future the available buttons should
	// be selected from the file type of the selected file
	html += info + deleteButton + translateIDsButton + joinPairedEndsButton + demultiplexButton;// + testButton;

	// render the HTML
	fo.innerHTML = html;
    };

    widget.updateFileFields = function () {
	var widget = Retina.WidgetInstances.kbupload[1];

	// reset the validation
	var status = document.getElementById('metadataValidationDiv');
	if (status) {
	    widget.metaDataValidated = false;
	    status.className = "alert";
	    status.innerHTML = "<b>validation required</b>";
	} else {
	    widget.metaDataValidated = true;
	}

	// get the files information from the DataStore
	var inbox = stm.DataStore.inbox;

	// hash the files by ending
	var files = {};
	for (var i in inbox) {
	    if (inbox.hasOwnProperty(i)) {
		if (inbox[i].attributes.hasOwnProperty('name')) {
		    var ending = inbox[i].attributes.name.substring(inbox[i].attributes.name.lastIndexOf('.') + 1);
		    if (! files.hasOwnProperty(ending)) {
			files[ending] = [];
		    }
		    files[ending].push({ "id": i, "name": inbox[i].attributes.name });
		}
	    }
	}

	// check which submission type we have
	var sub = document.getElementById('subtype');
	var subSel = sub.options[sub.selectedIndex].text;
	
	// get the template for the submission type
	var template = widget.templates[subSel];
	if (template) {

	    // extract the interface template
	    var interfaceTemplate = template["interface"];

	    // iterate over the inputs
	    var inP = interfaceTemplate.inputs;
	    for (var i=0;i<inP.length; i++) {

		// there is a filetype, this field must be updated
		if (inP[i].hasOwnProperty('filetype') && inP[i].filetype != null && inP[i].filetype.length) {

		    // this is a multiselect, construct a data array
		    if (inP[i].type == 'multiselect') {
			var opts = [];
			for (var h=0; h<inP[i].filetype.length; h++) {
			    if (files.hasOwnProperty(inP[i].filetype[h])) {
				for (var j=0; j<files[inP[i].filetype[h]].length; j++) {
				    opts.push(files[inP[i].filetype[h]][j]);
				}
			    }
			}
			
			// get the listselect, fill it with this data and render it
			if (document.getElementById('submissionFieldDiv'+inP[i].aweVariable)) {
			    widget.listSelects[i].settings.data = opts;
			    widget.listSelects[i].settings.target = document.getElementById('submissionFieldDiv'+inP[i].aweVariable);
			    widget.listSelects[i].render();
			}
		    }
		    // this is a dropdown, create options
		    else if (inP[i].type == 'dropdown') {
			if (document.getElementById('submissionField'+inP[i].aweVariable)) {
			    var opts = "";
			    for (var h=0; h<inP[i].filetype.length; h++) {
				if (files.hasOwnProperty(inP[i].filetype[h])) {
				    for (var j=0; j<files[inP[i].filetype[h]].length; j++) {
					opts += "<option value='"+files[inP[i].filetype[h]][j].id+"'>"+files[inP[i].filetype[h]][j].name+"</option>";
				    }
				}
			    }

			    // put the options into the innerHTML of the select
			    document.getElementById('submissionField'+inP[i].aweVariable).innerHTML = opts;
			}
		    }
		}
	    }
	}
    };

    /*
     * EVENTS
     */

    // callback for the login widget
    // this is issued on login and logout
    widget.authenticated = function (isAuthenticated, token) {
	var widget = Retina.WidgetInstances.kbupload[1];

	// clear file information box
	document.getElementById('fileOptions').innerHTML = "";

	// clear the token
	widget.token = null;

	// a user is successfully authenticated, show the appropriate data
	if (isAuthenticated) {
	    document.getElementById('authorized_section').style.display = "";
	    document.getElementById('unauthorized_section').style.display = "none";
	    Workspace.init(RetinaConfig.workspace || null, { "token": token } );
	    widget.token = token;
	    widget.updateInbox();
	    widget.getWorkspaces();
	}
	// the user logged out or login failed, hide content that requires authentication
	else {
	    document.getElementById('unauthorized_section').style.display = "";
	    document.getElementById('authorized_section').style.display = "none";	    
	    Workspace.init();
	}
    };

    // called from the submission in case a new workspace is requested for the submission result
    widget.createNewWorkspace = function () {
	var widget = Retina.WidgetInstances.kbupload[1];

	// check if the user supplied a name for the new workspace
	var n = document.getElementById('newWorkspaceNameField');
	if (! n.value.length) {
	    n.focus();
	    alert('you must select a name to create a new workspace');
	    return;
	}

	// we have a name, try to create a workspace
	Workspace.create_workspace({workspace: n.value}).done(function(data){
	    Retina.WidgetInstances.kbupload[1].newWorkspaceName = n.value;
	    document.getElementById('newWorkspaceName').style.display = "none";
	    Retina.WidgetInstances.kbupload[1].getWorkspaces();
	}).fail(function(err){
	    // something went wrong (e.g. the name already existed)
	    // tell the user the error message from the workspace service
	    Retina.WidgetInstances.kbupload[1].newWorkspaceName = "";
	    alert(err.error.error.split(/\n/)[0]);
	});
    };

    // validate if all required slots for the current pipeline are filled.
    // if everything is ok, start the pipeline
    // issued when the user clicks the submit button
    widget.validateSlots = function () {
	var widget = Retina.WidgetInstances.kbupload[1];

	// get the interface part of the template
	var templateName = document.getElementById('subtype').options[document.getElementById('subtype').selectedIndex].text;
	var iT = widget.templates[templateName]["interface"];
	var hasMetadata = widget.templates[templateName].hasOwnProperty('metadata');

	// the validation is not yet in place, default to true
	// in future default to false and perform validation
	var valid = true;
	var errors = [];

	if (hasMetadata && ! widget.metaDataValidated) {
	    errors.push("You must first validate the selected metadata file.");
	    valid = false;
	}

	// if the validation succeeds, submit the job to AWE
	if (valid) {
	    widget.submitToAWE();
	}
	// there were errors in the validation, tell the user about them
	else {
	    alert(errors.join("\n"));
	}
    };

    // perform a submission to AWE
    // issued when the user clicks submit and the validateSlots function succeeds
    widget.submitToAWE = function (attributesNode) {
	var widget = Retina.WidgetInstances.kbupload[1];
	
	// check which submission type we have
	var sub = document.getElementById('subtype');
	var subSel = sub.options[sub.selectedIndex].text;
	
	// get the AWE template for the submission type
	var template = widget.templates[subSel];
	var aweTemplate = template.awe;
	var interfaceTemplate = template["interface"];

	// fill in info section
	aweTemplate.info = {
	    "pipeline": RetinaConfig.awe.pipeline,
	    "name": subSel,
	    "project": RetinaConfig.awe.project,
	    "user": widget.user,
	    "clientgroups": RetinaConfig.awe.clientgroups,
	    "noretry": true
	};

	// retrieve variables to replace
	var replacements = { "SHOCK": RetinaConfig.shock,
			     "WORKSPACE": document.getElementById('workspaceSelector').options[document.getElementById('workspaceSelector').selectedIndex].value,
			     "WORKSPACEURL": RetinaConfig.workspace };
	for (var i=0; i<interfaceTemplate.inputs.length; i++) {
	    if (interfaceTemplate.inputs[i].hasOwnProperty('aweVariable') && interfaceTemplate.inputs[i].aweVariable) {
		var item = document.getElementById('submissionField'+interfaceTemplate.inputs[i].aweVariable);
		if (interfaceTemplate.inputs[i].type == "dropdown") {
		    replacements[interfaceTemplate.inputs[i].aweVariable+"FileName"] = item.options[item.selectedIndex].text;
		    replacements[interfaceTemplate.inputs[i].aweVariable] = item.options[item.selectedIndex].value;
		} else if (interfaceTemplate.inputs[i].type == "radio") {
		    var items = document.getElementsByName('submissionField'+interfaceTemplate.inputs[i].aweVariable);
		    for (var j=0; j<items.length;j++) {
			if (items[j].checked) {
			    replacements[interfaceTemplate.inputs[i].aweVariable] = items[j].value;
			}
		    }
		} else if (interfaceTemplate.inputs[i].type == "checkbox") {
		    if (item.checked) {
			replacements[interfaceTemplate.inputs[i].aweVariable] = "true";
		    } else {
			replacements[interfaceTemplate.inputs[i].aweVariable] = "false";
		    }
		} else if (interfaceTemplate.inputs[i].type == "multiselect") {
		    var fileNodes = [];
		    var fileNames = [];
		    for (var j=0; j<item.options.length; j++) {
			fileNodes.push(item.options[j].value);
			fileNames.push(item.options[j].text);
		    }
		    replacements[interfaceTemplate.inputs[i].aweVariable+"FileName"] = fileNames.join(",");
		    replacements[interfaceTemplate.inputs[i].aweVariable] = fileNodes.join(",");
		} else {
		    replacements[interfaceTemplate.inputs[i].aweVariable] = item.value;
		}
	    }
	}

	// replace variables in the AWE workflow
	var aweString = JSON.stringify(aweTemplate);
	for (var i in replacements) {
	    if (replacements.hasOwnProperty(i)) {
		aweString = aweString.replace(new RegExp("\#\#" + i + "\#\#", "g"), replacements[i]);
	    }
	}
	aweString = aweString.replace(new RegExp("\#\#TOKEN\#\#", "g"), widget.token);
	aweTemplate = JSON.parse(aweString);

	// perform the submission
	var url = RetinaConfig.awe.url +"/job";
	var aFile = [ JSON.stringify(aweTemplate) ];
	var oMyBlob = new Blob(aFile, { "type" : "text\/json" });
	var fd = new FormData();
	fd.append('upload', oMyBlob);
	jQuery.ajax(url, {
	    contentType: false,
	    processData: false,
	    data: fd,
	    success: function(data) {

		// check if there were submission errors
		if (data.hasOwnProperty('error') && data.error && data.error.length) {
		    alert('Your submission failed');
		    console.log(data);
		} else {
		
		    // the submission succeeded, query the current status and feed back to the user
		    jQuery.ajax(RetinaConfig.awe.url+"/job/"+data.data.id, { headers: { "Authorization": "OAuth "+Retina.WidgetInstances.kbupload[1].token,
											"Datatoken": Retina.WidgetInstances.kbupload[1].token },
									     success: function(data) {
										 alert('Your submission is complete. The current status is '+data.data.state);
										 Retina.WidgetInstances.kbupload[1].updateInbox();
									     }});
		}
	    },
	    error: function(jqXHR, error){
		// something went wrong with the submission
		alert('Your submission failed.');
		console.log( "error" );
		console.log(jqXHR);
	    },
	    headers: { "Authorization": "OAuth "+widget.token,
		       "Datatoken": widget.token },
	    type: "POST"
	});
    };
    
    // retrieve the private workspaces available to the current user
    widget.getWorkspaces = function (cached) {
	var widget = Retina.WidgetInstances.kbupload[1];

	// use the version in the DataStore, do not reload
	if (cached && stm.DataStore.hasOwnProperty('workspaces')) {
	     // get the result from the DataStore
	    var data = stm.DataStore.workspaces;

	    // get the DOM element that holds the workspace selection
	    var sel = document.getElementById('workspaceSelector');

	    // add the event listener to hide the name input unless 'create new' is selected
	    sel.addEventListener('change', function() {
		if (this.options[this.selectedIndex].value == "new") {
		    document.getElementById('newWorkspaceName').style.display = "";
		} else {
		    document.getElementById('newWorkspaceName').style.display = "none";
		}
	    });

	    // create the options for the workspace selector
	    var opts = "";
	    for (var i=0;i<data.length;i++) {

		// if a new workspace has just been created, it is selected
		var isSelected = "";
		if (Retina.WidgetInstances.kbupload[1].newWorkspaceName && Retina.WidgetInstances.kbupload[1].newWorkspaceName == data[i][0]) {
		    isSelected = " selected";
		}
		opts += "<option"+isSelected+">"+data[i][0]+"</option>";
	    }
	    opts += "<option value='new'>- create new -</option>";
	    
	    // fill the select box with the options
	    sel.innerHTML = opts;
	    
	    // if there is only one entry, the user has no workspaces yet, show the workspace name input
	    if (sel.options.length == 1) {
		document.getElementById('newWorkspaceName').style.display = "";
	    }

	    return;
	}

	// call the Workspace service
	Workspace.list_workspaces({excludeGlobal: 1}).done(function(data){

	    // store the result in the DataStore
	    stm.DataStore.workspaces = data;

	    // get the DOM element that holds the workspace selection
	    var sel = document.getElementById('workspaceSelector');

	    if (sel) {
		
		// add the event listener to hide the name input unless 'create new' is selected
		sel.addEventListener('change', function() {
		    if (this.options[this.selectedIndex].value == "new") {
			document.getElementById('newWorkspaceName').style.display = "";
		    } else {
			document.getElementById('newWorkspaceName').style.display = "none";
		    }
		});
		

		// create the options for the workspace selector
		var opts = "";
		for (var i=0;i<data.length;i++) {

		    // if a new workspace has just been created, it is selected
		    var isSelected = "";
		    if (Retina.WidgetInstances.kbupload[1].newWorkspaceName && Retina.WidgetInstances.kbupload[1].newWorkspaceName == data[i][0]) {
			isSelected = " selected";
		    }
		    opts += "<option"+isSelected+">"+data[i][0]+"</option>";
		}
		opts += "<option value='new'>- create new -</option>";
		
		// fill the select box with the options
		sel.innerHTML = opts;
		
		// if there is only one entry, the user has no workspaces yet, show the workspace name input
		if (sel.options.length == 1) {
		    document.getElementById('newWorkspaceName').style.display = "";
		}
	    }
	});
    };

    // progress event for the file upload
    // this updated the progress bar
    widget.onProgress = function (event) {
	var widget = Retina.WidgetInstances.kbupload[1];
	var loaded = event.loaded + (SHOCK.currentChunk * SHOCK.chunkSize);
	var total = SHOCK.file.size;
	var percent = parseFloat(loaded / total * 100);
	widget.progressCurrent.innerHTML = stm.prettySize(loaded);
	widget.pBarInner.style.width = percent+"%";
    };

    // update the uploaded file with attributes indicating that it is a staging area file
    // this is called when a file upload succeeds
    widget.uploadComplete = function (data) {
	
	// create the metadata structure for the staging area
	var inboxAttributes = { "user": Retina.WidgetInstances.kbupload[1].user,
				"type": "inbox",
				"name": data.attributes.incomplete_name };

	// issue the node update through the SHOCK library
	SHOCK.update_node(data.id, inboxAttributes, Retina.WidgetInstances.kbupload[1].updateInbox);
    };

    // update the contents of the staging area
    widget.updateInbox = function () {
	var widget = Retina.WidgetInstances.kbupload[1];

	// get the staging area files from SHOCK and call the showShockResult function
	// once the file information is available
	SHOCK.get_all_nodes(Retina.WidgetInstances.kbupload[1].showShockResult,"?query&limit=9999&type=inbox&user="+Retina.WidgetInstances.kbupload[1].user);
	
	// get the pipeline status information from AWE and call the showAWEResult function
	jQuery.ajax(RetinaConfig.awe.url+"/job?query&info.user="+widget.user+"&info.project=data-importer", {
	    success: function (data) {
		Retina.WidgetInstances.kbupload[1].showAWEResult(data);
	    },
	    headers: { "Authorization": "OAuth "+Retina.WidgetInstances.kbupload[1].token,
		       "Datatoken": Retina.WidgetInstances.kbupload[1].token }
	});
    };

    // issue a download for the current template in JSON format
    widget.jsonTemplate = function (type) {

	// stringify the JSON structure of the template with nice padding and issue the stm saveAs function
	stm.saveAs(JSON.stringify(Retina.WidgetInstances.kbupload[1].templates[type].metadata, null, 2), Retina.WidgetInstances.kbupload[1].templates[type].name+".json");
    };

    // issue a download for the current template in Excel format
    // the type and an empty Excel workbook object is passed to this function
    widget.excelTemplate = function (type, wb) {
	var widget = Retina.WidgetInstances.kbupload[1];

	// get the template structure
	var template = Retina.WidgetInstances.kbupload[1].templates[type].metadata;
	
	// make sure optional template data is filled (the check_template function fills optional data with defaults)
	// this would also check if there are errors, but this should be done offline before a template is declared a
	// valid addition to the DataImporter
	var retVal = Retina.WidgetInstances.template_validator[1].check_template(template, 1);
	template = retVal.template;

	// initialize the Excel workbook counter
	var wbNum = 0;

	// these are for debugging, there is currently an issue with deep nesting
	// basic parsing works fine
	window.tgs = template.groups;
	window.wb = wb;

	// iterate over the template groups to find toplevel groups
	for (var i in template.groups) {
	    if (template.groups.hasOwnProperty(i)) {
		var group = template.groups[i];

		// if this is a toplevel group, the parsing needs to start
		if (group.toplevel) {

		    // the first worksheet already exists in the workbook, only
		    // change the name
		    if (wbNum == 0) {
			wb.worksheets[0].name = group.label;
		    }
		    // a new worksheet is needed for this group
		    else {
			wb.addWorksheet({ name: group.label });
		    }

		    // initialize the field counter (x-coordinate on the sheet)
		    var fieldNum = 0;

		    // iterate over the fields of the group
		    var flist = Retina.values(group.fields);
		    if (flist[0].hasOwnProperty('index')) {
			flist.sort(Retina.propSort('index'));
		    } else {
			flist.sort(Retina.propSort('label'));
		    }
		    for (var h=0; h<flist.length; h++) {

			// the setCell function takes the workbook indes, the column number,
			// the row number and the cell value
			var field = flist[h];
			wb.setCell(wbNum, fieldNum, 0, field.label);
			
			// if there is a description, put it in the second row
			if (field.description) {
			    wb.setCell(wbNum, fieldNum, 1, field.description);
			}
			
			// increment the field counter
			fieldNum++;
		    }
		    // increment the worksheet counter
		    wbNum++;
		    
		    // if the group has subgroups, parse them
		    if (group.hasOwnProperty('subgroups')) {

			// fillSubgroup is a separate function because it is called recursively to handle deep nesting
			var array = Retina.WidgetInstances.kbupload[1].fillSubgroup(template, group, wb, wbNum);
			group = array[0];
			wb = array[1];
			wbNum = array[2];
		    }
		}
	    }
	}
	
	// open a save dialog for the user through the stm.saveAs function
	stm.saveAs(xlsx(wb).base64, template.name+".xlsx", "data:application/vnd.openxmlformats-officedocument.spreadsheetml.sheet;base64,");
    };

    // subgroup parsing function
    // this calls itself recursively to handle deep nesting
    widget.fillSubgroup = function (template, group, wb, wbNum) {
	for (var h in group.subgroups) {
	    if (group.subgroups.hasOwnProperty(h)) {
		var subgroup = template.groups[h];
		if (group.subgroups[h].hasOwnProperty('prefix')) {
		    subgroup.prefix = group.subgroups[h].prefix;
		}
		subgroup.parent = group.name;
		if (subgroup.hasOwnProperty('fields')) {

		    // add a worksheet for this group
		    // the name might have a prefix (see below)
		    wb.addWorksheet({ name: subgroup.prefix ? subgroup.prefix +"-"+subgroup.label : subgroup.label });

		    // add a reference cell for the parent group
		    wb.setCell(wbNum, 0, 0, subgroup.parent);
		    wb.setCell(wbNum, 0, 1, "name of the "+subgroup.parent+" of this "+subgroup.name);

		    // start with offset 1 due to the reference cell
		    var fieldNum = 1;

		    // iterate over the fields and create a cell for each
		    for (var h in subgroup.fields) {
			if (subgroup.fields.hasOwnProperty(h)) {
			    var field = subgroup.fields[h];
			    wb.setCell(wbNum, fieldNum, 0, field.label ? field.label : (field.name ? field.name : h));

			    // if the is a descriptions, add it in the cell below
			    if (field.description) {
				wb.setCell(wbNum, fieldNum, 1, field.description);
			    }
			    // increment the field counter
			    fieldNum++;
			}
		    }
		    // increment the worksheet counter
		    wbNum++;
		} else {
		    // if a group does not have fields, it does not create its own spreadsheet
		    // instead it adds its name as a prefix to the child groups
		    for (var j in subgroup.subgroups) {
			if (subgroup.subgroups.hasOwnProperty(j)) {
			    subgroup.subgroups[j].prefix = h;
			}
		    }
		}
	
		// if there are subgroups, make a recursive call to this function
		if (subgroup.hasOwnProperty('subgroups')) {
		    var array = Retina.WidgetInstances.kbupload[1].fillSubgroup(template, subgroup, wb, wbNum);
		    group = array[0];
		    wb = array[1];
		    wbNum = array[2];
		}
	    }
	}

	return [group, wb, wbNum];
    };
    
    // open an empty Excel workbook from the data directory, use the xlsx library
    // to create a javascript object from it and call the excelTemplate function, passing
    // the object and the selected type
    widget.xlsInit = function (type) {
	// issue an XMLHttpRequest to load the empty Excel workbook from disk
	var xhr = new XMLHttpRequest();
	var method = "GET";
	var base_url = "data/Workbook1.xlsx";
	if ("withCredentials" in xhr) {
	    xhr.open(method, base_url, true);
	} else if (typeof XDomainRequest != "undefined") {
	    xhr = new XDomainRequest();
	    xhr.open(method, base_url);
	} else {
	    alert("your browser does not support CORS requests");
	    console.log("your browser does not support CORS requests");
	    return undefined;
	}

	xhr.responseType = 'arraybuffer';

	xhr.onload = function() {

	    // the file is loaded, create a javascript object from it
	    var wb = xlsx(xhr.response);

	    // call the excelTemplate function with the type and the workbook object
	    Retina.WidgetInstances.kbupload[1].excelTemplate(type, wb);
	}

	xhr.send();
    };

    // load the metadata template from disc and store them in the widget
    widget.loadTemplates = function () {
	var widget = Retina.WidgetInstances.kbupload[1];

	var templateNames = RetinaConfig.templates;
	var promises = [];
	for (var i=0;i<templateNames.length;i++) {
	    promises.push( jQuery.ajax("data/"+templateNames[i]+".json", { method: "GET",
									   dataType: "text",
									   cache: false,
									   beforeSend: function( xhr ) {
									       xhr.tname = templateNames[i];
									   },
									   success: function(data,status,jqXHR) {
									       var niceName = jqXHR.tname;
									       niceName = niceName.replace(/_/g, " ");
									       Retina.WidgetInstances.kbupload[1].templates[niceName] = JSON.parse(data);
									       if (document.getElementById('subtype')) {
										   Retina.WidgetInstances.kbupload[1].showSubtype(document.getElementById('subtype'));
									       }
									   }
									 }) );
	}
	
	// when all templates are loaded, create the submission area
	jQuery.when.apply(this, promises).then(function() {

	    // initialize the submission area
	    Retina.WidgetInstances.kbupload[1].submissionDisplay(document.getElementById('submissionSection'));
	});
    };

    // check if the selected metadata file contains data valid for the template of this pipeline
    widget.validateMetadata = function(sel) {

	// get the template for the selected submission type
	var templateName = document.getElementById('subtype').options[document.getElementById('subtype').selectedIndex].text;
	var md = Retina.WidgetInstances.template_validator[1].check_template(Retina.WidgetInstances.kbupload[1].templates[templateName]["metadata"], 1);
	md = md.template;
	Retina.WidgetInstances.template_validator[1].template = jQuery.extend(true, {}, Retina.WidgetInstances.kbupload[1].templates[templateName]["metadata"]);

	// get the shock node id for the selected metadata file
	var node = sel.options[sel.selectedIndex].value;

	// get the metadata validation status field
	var status = document.getElementById('metadataValidationDiv');

	// check if this has already been transformed to JSON
	if (Retina.WidgetInstances.kbupload[1].validatedTemplates.hasOwnProperty(node)) {
	    Retina.WidgetInstances.kbupload[1].metaDataValidated = true;
	    status.className = "alert alert-success";
	    status.innerHTML = "<b>Your metadata is valid</b>";
	    return;
	}
	
	// check if a parsed template is available for this node
	if (Retina.WidgetInstances.kbupload[1].jsonTemplates[node]) {

	    // adjust name / label differences in parsed template
	    var d = jQuery.extend(true, {}, Retina.WidgetInstances.kbupload[1].jsonTemplates[node]);
	    for (var i in d) {
		if (d.hasOwnProperty(i)) {
		    for (var j in md.groups) {
			if (md.groups.hasOwnProperty(j)) {
			    if (md.groups[j].label == i) {
				if (i != j) {
				    if (d[i].hasOwnProperty(0)) {
					d[j] = [];
					for (var k=0;k<d[i].length;k++) {
					    d[j][k] = {};
					    for (var h in md.groups[j].fields) {
						if (md.groups[j].fields.hasOwnProperty(h)) {
						    d[j][k][h] = d[i][k].hasOwnProperty(md.groups[j].fields[h].label) ? d[i][k][md.groups[j].fields[h].label] : (md.groups[j].fields[h].hasOwnProperty('default') ? md.groups[j].fields[h]['default'] : null);
						}
					    }
					}
					delete d[i];
				    } else {
					d[j] = {};
					for (var h in md.groups[j].fields) {
					    if (md.groups[j].fields.hasOwnProperty(h)) {
						d[j][h] = d[i].hasOwnProperty(md.groups[j].fields[h].label) ? d[i][md.groups[j].fields[h].label] : (md.groups[j].fields[h].hasOwnProperty('default') ? md.groups[j].fields[h]['default'] : null);
						if (h != md.groups[j].fields[h].label) {
						    delete d[md.groups[j].fields[h].label];
						}
					    }
					}
					delete d[i];
				    }
				} else {
				    if (d[i].hasOwnProperty(0)) {
					for (var k=0;k<d[i].length;k++) {
					    for (var h in md.groups[j].fields) {
						if (md.groups[j].fields.hasOwnProperty(h)) {
						    if (h != md.groups[j].fields[h].label) {
							d[i][k][h] = d[i][k].hasOwnProperty(md.groups[j].fields[h].label) ? d[i][k][md.groups[j].fields[h].label] : (md.groups[j].fields[h].hasOwnProperty('default') ? md.groups[j].fields[h]['default'] : null);
							delete d[i][k][md.groups[j].fields[h].label];
						    } else {
							if (! d[i][k].hasOwnProperty(h)) {
							    d[i][k][h] = md.groups[j].fields[h].hasOwnProperty('default') ? md.groups[j].fields[h]['default'] : null;
							}
						    }
						}
					    }
					}
				    } else {
					for (var h in md.groups[j].fields) {
					    if (md.groups[j].fields.hasOwnProperty(h)) {
						if (h != md.groups[j].fields[h].label) {
						    d[i][h] = d[i].hasOwnProperty(md.groups[j].fields[h].label) ? d[i][md.groups[j].fields[h].label] : (md.groups[j].fields[h].hasOwnProperty('default') ? md.groups[j].fields[h]['default'] : null);
						    delete d[i][md.groups[j].fields[h].label];
						} else {
						    if (! d[i].hasOwnProperty(h)) {
							d[i][h] = md.groups[j].fields[h].hasOwnProperty('default') ? md.groups[j].fields[h]['default'] : null;
						    }
						}
					    }
					}
				    }
				}
			    }
			}
		    }
		}
	    }

	    // check if any data matched the template
	    var num = 0;
	    for (var i in d) {
		num++;
		break;
	    }
	    if (num == 0) {
		status.className = "alert alert-error";
		status.innerHTML = "<b>Your metadata did not match the template.</b><br>Did you select a metadata file that corresponds to the template?";
		Retina.WidgetInstances.kbupload[1].metaDataValidated = false;
		return;
	    }

	    // there is JSON formatted data available, check it against the template
	    var retval = Retina.WidgetInstances.template_validator[1].validate_data(d, true);
	    if (retval.hasOwnProperty('errors')) {
		status.className = "alert alert-error";
		status.innerHTML = "<b>Your metadata did not validate</b><br>" + retval.errors.join("<br>");
		Retina.WidgetInstances.kbupload[1].metaDataValidated = false;
	    } else {
		status.className = "alert alert-success";
		status.innerHTML = "<b>Your metadata is valid</b>";
		document.getElementById('aweSubmitButton').setAttribute('disabled', 'disabled');
		SHOCK.create_node_from_JSON(retval.data, function(data){
		    var xls = sel.options[sel.selectedIndex].value;
		    Retina.WidgetInstances.kbupload[1].validatedTemplates[data.id] = xls;
		    sel.options[sel.selectedIndex].value = data.id;
		    Retina.WidgetInstances.kbupload[1].metaDataValidated = true;
		    document.getElementById('aweSubmitButton').removeAttribute('disabled');
		});
	    }
	    
	}
	// there is no template, so the validation failed basic formatting checks
	else {
	    status.className = "alert alert-error";
	    status.innerHTML = "<b>Your metadata did not validate</b><br>Your metadata has an invalid format.<br>Please use the template downloadable via the 'download Excel Template' button.";
	    Retina.WidgetInstances.kbupload[1].metaDataValidated = false;
	}
    };

    /*
     * HELPER FUNCTIONS
     */

    // create dots for awe steps
    widget.dots = function (stages) {
	var dots = '<span>';
	if (stages.length > 0) {
	    for (var i=0;i<stages.length;i++) {
		if (stages[i].state == 'completed') {
		    dots += '<span style="color: green;font-size: 19px; cursor: default;" title="completed: '+stages[i].cmd.description+'">&#9679;</span>';
		} else if (stages[i].state == 'in-progress') {
		    dots += '<span style="color: blue;font-size: 19px; cursor: default;" title="in-progress: '+stages[i].cmd.description+'">&#9679;</span>';
		} else if (stages[i].state == 'queued') {
		    dots += '<span style="color: orange;font-size: 19px; cursor: default;" title="queued: '+stages[i].cmd.description+'">&#9679;</span>';
		} else if (stages[i].state == 'suspend') {
		    dots += '<span style="color: red;font-size: 19px; cursor: default;" title="error: '+stages[i].cmd.description+'">&#9679;</span>';
		} else if (stages[i].state == 'init' || stages[i].state == 'pending') {
		    dots += '<span style="color: gray;font-size: 19px; cursor: default;" title="'+stages[i].state+': '+stages[i].cmd.description+'">&#9679;</span>';
		}
	    }
	}
	
	dots += "</span>";
	
	return dots;
    };

    // function to convert Excel metadata files to JSON format
    widget.excelToJSON = function (node) {
	var widget = Retina.WidgetInstances.kbupload[1];
	var xhr = new XMLHttpRequest();
    	var method = "GET";
    	var url = SHOCK.url+'/node/'+node+'?download_raw';
    	if ("withCredentials" in xhr) {
    	    xhr.open(method, url, true);
    	} else if (typeof XDomainRequest != "undefined") {
    	    xhr = new XDomainRequest();
    	    xhr.open(method, url);
    	} else {
    	    alert("your browser does not support CORS requests");
    	    console.log("your browser does not support CORS requests");
    	    return undefined;
    	}

    	xhr.responseType = 'arraybuffer';
	xhr.setRequestHeader('Authorization', "OAuth "+widget.token);
	xhr.id = node;

    	xhr.onload = function() {

    	    // the file is loaded, create a javascript object from it
    	    var wb = xlsx(xhr.response);

	    // determine the current template type
	    var type = document.getElementById('subtype').options[document.getElementById('subtype').selectedIndex].text;

	    // get the metadata template for this type
	    var template = Retina.WidgetInstances.kbupload[1].templates[type].metadata;

	    if (! template) {
		return;
	    }

	    // store the result data
    	    var parsedData = {};

	    // get the label to group and label to field mapping
	    var l2g = {};
	    var l2f = {};
	    for (var i in template.groups) {
		if (template.groups.hasOwnProperty(i)) {
		    l2g[template.groups[i].label || i] = i;
		    l2f[template.groups[i].label || i] = {};
		    for (var h in template.groups[i].fields) {
			if (template.groups[i].fields.hasOwnProperty(h)) {
			    l2f[template.groups[i].label || i][template.groups[i].fields[h].label || h] = h;
			}
		    }
		}
	    }
	    
	    // iterate over the worksheets to find all available groups
	    var groups = {};
	    for (var i=0; i<wb.worksheets.length; i++) {
		var ws = wb.worksheets[i];
		if (ws.name == "README") {
		    continue;
		}
		groups[ws.name] = 1;
	    }

	    // iterate over the worksheets to extract the data
	    for (var i=0; i<wb.worksheets.length; i++) {

		// get the current worksheet from the workbook
		var ws = wb.worksheets[i];

		// check if this group is in the template
		if (! l2g.hasOwnProperty(ws.name)) {
		    continue;
		}

		// if cell A1 is empty, this sheet has no data
		if (typeof ws.data[0][0] === "undefined") {
		    return;
		}

		// check if cell A1 contains a group name
		if (groups.hasOwnProperty(ws.data[0][0].value)) {

		    // check if the user was mistakenly using the comment field
		    var rowIndex = 2;
		    if (template.groups[l2g[ws.name]].fields[l2f[ws.name][ws.data[0][1].value]].description != ws.data[1][1].value) {
			rowIndex = 1;
		    }

		    // this is a subgroup, iterate over the datasets
		    for (var j=rowIndex;j<ws.data.length;j++) {
			if (ws.data[j].length == 0) {
			    break;
			}

			// create the current dataset
			var ds = {};
			for (var h=0;h<ws.data[0].length; h++) {
			    if (typeof ws.data[0][h] === "undefined") {
				return;
			    }
			    if (template.groups[l2g[ws.data[0][0].value]].fields[l2f[ws.name][ws.data[0][h].value]].type == "text") {
				ds[ws.data[0][h].value] = (typeof ws.data[rowIndex] === "undefined" || typeof ws.data[rowIndex][h] === "undefined") ? null : ws.data[rowIndex][h].value + "";
			    } else {
				ds[ws.data[0][h].value] = (typeof ws.data[rowIndex] === "undefined" || typeof ws.data[rowIndex][h] === "undefined") ? null : ws.data[rowIndex][h].value;
			    }
			}

			// push the dataset into the parent object
			if (template.groups[l2g[ws.data[0][0].value]].subgroups[ws.name].type == "list") {
			    parsedData[ws.data[0][0].value][ws.data[rowIndex][0].value][ws.name].push(ds);
			} else {
			    parsedData[ws.data[0][0].value][ws.data[rowIndex][0].value][ws.name] = ds;
			}
		    }
		}
		// this is a toplevel group
		else {
		    parsedData[ws.name] = [];

		    // check if the user was mistakenly using the comment field
		    var rowIndex = 2;
		    if (template.groups[l2g[ws.name]].fields[l2f[ws.name][ws.data[0][0].value]].description != ws.data[1][0].value) {
			rowIndex = 1;
		    }

		    for (var j=rowIndex;j<ws.data.length;j++) {
			if (ws.data[j].length == 0) {
			    break;
			}
			var dataRow = {};
			for (var h=0;h<ws.data[0].length; h++) {
			    if (typeof ws.data[0][h] === "undefined") {
				return;
			    }
			    dataRow[ws.data[0][h].value] = (typeof ws.data[j] === "undefined" || typeof ws.data[j][h] === "undefined") ? null : ws.data[j][h].value+"";
			}
			parsedData[ws.name].push(dataRow);
		    }
		    if (!(template.groups.hasOwnProperty(l2g[ws.name]) && template.groups[l2g[ws.name]].hasOwnProperty('type') && template.groups[l2g[ws.name]].type == 'list')) {
			parsedData[ws.name] = parsedData[ws.name][0];
		    }
		} 
	    }
	   Retina.WidgetInstances.kbupload[1].jsonTemplates[xhr.id] = parsedData;
    	}

    	xhr.send();
    };
})();
