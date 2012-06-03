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
                    var width  = img.width();
                    var height = img.height();
                    var paper = Raphael('image', width, height);
                    var image = paper.image(url, 0, 0, width, height);
                    $.ajax({
                        url: '/api/face',
                        data: { url: url },
                        dataType: 'json',
                        success: function (res) {
                            var r = paper.path('M' + res.right_eye.x + ',' + res.right_eye.y + 'L' + res.right_eye.x + ',' + height);
                            var l = paper.path('M' + res.left_eye.x  + ',' + res.left_eye.y  + 'L' + res.left_eye.x  + ',' + height);
                            r.attr('stroke', 'white');
                            l.attr('stroke', 'white');
                        }
                    });
                    img.remove();
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
