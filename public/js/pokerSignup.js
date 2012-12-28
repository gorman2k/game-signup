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


$(function(){
    function formatDate(dates) {
        dates.each(function(){
            //get date
            formattedDate = $(this).text();

            //format it
            var d = moment(formattedDate, "YYYY-MM-DDTHH:mm");

            //replace it
            $(this).text(d.format("dddd, MMMM Do YYYY, h:mm a"));
        });
    };

    formatDate($('.dateformat'));
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
