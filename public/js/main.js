(function () {
    var router = {
        '^/result/': function () {
            var textarea = $('textarea.tweet');
            $('.share.twitter').click(function (e) {
                e.preventDefault();
                $('#tw-modal').on('shown', function () {
                    textarea.focus();
                }).modal('show');
            });
            textarea.keyup(function () {
                var count = 80 - textarea.val().length;
                var group = $(this).closest('.control-group');
                $('.charcount').text(count);
                if (count < 0) {
                    group.addClass('error');
                    $('#submit').attr('disabled', 'disabled');
                } else {
                    group.removeClass('error');
                    $('#submit').removeAttr('disabled');
                }
            });
        }
    };

    $(function () {
        var pathname = window.location.pathname;
        $.each(router, function (k, v) {
            if (pathname.match(k)) {
                v();
            }
        });
    });
}());
