var ExtensionPreprocessingJS = {
    run: function(arguments) {
        var canonical = document.querySelector('link[rel="canonical"]');
        var site = document.querySelector('meta[property="og:site_name"]');
        arguments.completionFunction({
            url: document.location.href,
            title: document.title.slice(0, 8000),
            selectedText: window.getSelection().toString(),
            canonicalURL: canonical ? canonical.href : '',
            siteName: site ? site.content.slice(0, 1000) : document.location.hostname
        });
    }
};
