mw.loader.using('mediawiki.user').then(function () {

    mw.user.getGroups().then(function (groups) {

        console.log('User groups:', groups);

        if (groups.includes('sysop')) {

            console.log('User is an administrator.');

        }

    });

});

//	hide the sidebar navigation.
//document.querySelector('#sb-pri-tgl-btn').style.display = 'none';
//document.getElementById('sb-pri-tgl-btn').remove();

// Function to convert Blue spice iframe to real iframes
function convertMediaWikiIframesToReal() {
    // We have to use var instead of let for BlueSpice compatibility
    // Look for paragraphs that contain escaped iframe tags

    var paragraphs = document.querySelectorAll('p');

    for (var i = 0; i < paragraphs.length; i++) {

        var paragraph = paragraphs[i];

        var content = paragraph.innerHTML;


        // Check if this paragraph contains an escaped iframe

        if (content.indexOf('&lt;iframe') !== -1 && content.indexOf('&lt;/iframe&gt;') !== -1) {


            // Find any links inside this iframe text
            var links = paragraph.querySelectorAll('a.external');

            if (links.length > 0) {

                // Use the href from the first link as our iframe src
                var url = links[0].href;

                // Create an actual iframe element
                var iframe = document.createElement('iframe');
                iframe.src = url;
                iframe.width = "100%";
                iframe.height = "2400px";
                iframe.style.border = "none";


                // Replace the paragraph with the iframe
                if (paragraph.parentNode) {
                    paragraph.parentNode.replaceChild(iframe, paragraph);
                    console.log('Converted MediaWiki iframe to real iframe with URL: ' + url);
                }
            }
        }
    }

    // now hide the #title-section
    var titleSection = document.querySelector('#title-section');

    // We look for this tag in the #title-section <span className="mw-page-title-main">Rt-search</span>
    var pageTitle = titleSection.querySelector('span.mw-page-title-main');
    if (pageTitle && pageTitle.textContent === 'Rt-search') {
        titleSection.style.display = 'none';

        // now we hide the form #bs-extendedsearch-box
        var searchBox = document.querySelector('#bs-extendedsearch-box');
        searchBox.style.display = 'none';

        // make the background grey
        var body = document.querySelector('body');
        body.style.backgroundColor = '#e0e0e0';

        // now we hide the aftercontent
        var afterContent = document.querySelector('#aftercontent');
        afterContent.style.display = 'none';


        var main = document.querySelector('#main');
        main.style.backgroundColor = '#e0e0e0';

    }

}

// page load
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', convertMediaWikiIframesToReal);
} else convertMediaWikiIframesToReal();