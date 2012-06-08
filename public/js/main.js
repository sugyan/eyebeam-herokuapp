(function () {
    var router = {
        '^/custom/': function () {
            var canvas = $('canvas#image').get(0);
            var ctx = canvas.getContext('2d');
            var img = new Image();
            img.src = '/img/sample.jpg';
            img.onload = function () {
                // TODO check width and height
                ctx.drawImage(img, 0, 0);
            };
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
