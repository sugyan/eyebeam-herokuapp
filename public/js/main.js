(function () {
    var router = {
        '^/result/': function () {
            $('.share').click(function (e) {
                e.preventDefault();
                if ($(this).hasClass('twitter')) {
                    $('#tw-modal').on('shown', function () {
                        $(this).find('textarea').focus();
                    }).modal('show');
                }
                if ($(this).hasClass('facebook')) {
                    $('#fb-modal').on('shown', function () {
                        $(this).find('textarea').focus();
                    }).modal('show');
                }
            });
            $('textarea').each(function (i, e) {
                var textarea = $(e);
                var maxchars = {
                    twitter: 80,
                    facebook: 300
                }[textarea.attr('class')];
                textarea.keyup(function () {
                    var count = maxchars - textarea.val().length;
                    var group = $(this).closest('.control-group');
                    $(this).closest('form').find('.charcount').text(count);
                    if (count < 0) {
                        group.addClass('error');
                        $('.submit').attr('disabled', 'disabled');
                    } else {
                        group.removeClass('error');
                        $('.submit').removeAttr('disabled');
                    }
                });
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
