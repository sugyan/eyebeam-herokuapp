(function () {
    var router = {
        '^/image$': function () {
            var retry = 0;
            var url = $('#s3_url').val();
            var load = function (url) {
                var img = $('<img>', {
                    src: url
                }).hide();
                img.load(function () {
                    $('#message').remove();
                    var paper = Raphael('image', img.width(), img.height());
                    var image = paper.image(url, 0, 0, img.width(), img.height());
                });
                img.error(function () {
                    img.remove();
                    if (retry++ > 5) {
                        $('#message').text('読み込みに失敗しました。');
                    } else {
                        window.setTimeout(function () {
                            load(url);
                        }, 2000);
                    }
                });
                $('#image').append(img);
            };
            load(url);
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
