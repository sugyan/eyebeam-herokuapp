(function () {
    var router = {
        '^/image$': function () {
            console.log($('#s3_url').val());
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
