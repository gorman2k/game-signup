$(document).ready(function(){
    $('#signout').bind('click', function () {
        var signout = $.ajax({
            url:'/signout',
            type:'post'
        });

        signout.success(function () {
            window.location = '/'
        });
    })
});

$(document).ajaxComplete(function(event, request) {
    var type = request.getResponseHeader('X-Message-Type');
    var msg = request.getResponseHeader('X-Message');
    if (msg)
        $("#flash-message").html('<div class="flash '+type+'">'+msg+'</div>');
});

$(document).ready(function(){
    $('#signup').bind('click', function () {
        var href = $(this).attr('link');
        id = href.substr(href.lastIndexOf('/') + 1);
        var signup = $.ajax({
            url: '/game/' + id,
            type:'put'
        });

        signup.success(function () {
            $('#playerList').load('/game/' + id + '/playerList');
            $('#waitingList').load('/game/' + id + '/waitingList');
        })
    })
});

$(document).ready(function(){
    $('#remove').bind('click', function () {
        var href = $(this).attr('link');
        id = href.substr(href.lastIndexOf('/') + 1);
        var remove = $.ajax({
            url: '/game/' + id,
            type:'delete'
        });

        remove.success(function () {
            $('#playerList').load('/game/' + id + '/playerList');
            $('#waitingList').load('/game/' + id + '/waitingList');
        })
    })
});

$(function () {
    $('#datepicker').datetimepicker({
        dateFormat: 'yy-mm-dd',
        hour: 19,
        minute: 30,
        showOn: "button",
        buttonImage: "images/calendar.gif",
        buttonImageOnly: true
    });
});
