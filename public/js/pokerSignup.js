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
