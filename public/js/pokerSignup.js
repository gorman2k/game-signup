$(document).ajaxComplete(function(event, request) {
    var type = request.getResponseHeader('X-Message-Type');
    var msg = request.getResponseHeader('X-Message');
    if (msg)
        $("#flash-message").html('<div class="flash '+type+'">'+msg+'</div>');
});
