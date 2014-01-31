	    var sub = document.getElementById('subtype');
	    var subSel = sub.options[sub.selectedIndex].text;
	    var source = document.getElementById('selectedSequenceFiles');
	    var sourceNodeId = source.options[0].value;
	    var sourceNodeName = source.options[0].text;
	    var attributesData = { "user": Retina.WidgetInstances.kbupload[1].user,
				   "type": "processing",
				   "status": "submitted",
				   "pipeline": subSel,
				   "name": sourceNodeName,
				   "id": sourceNodeId };
	    SHOCK.create_node_from_JSON(attributesData).then( function(resultNode) {
		// create the attributes node, then submit to AWE
		widget.submitToAWE(resultNode.id);
	    });