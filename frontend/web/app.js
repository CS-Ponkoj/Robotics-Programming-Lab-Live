var userCode;

function getParamValue(pName) {
    var url = window.location.search.substring(1); //get rid of "?" in querystring
    var qArray = url.split('&'); //get key-value pairs
    for (var i = 0; i < qArray.length; i++) {
        var pArr = qArray[i].split('='); //split key and value
        if (pArr[0] == pName)
            return pArr[1]; //return value
    }
}



document.addEventListener('DOMContentLoaded', function () {
    require.config({
        paths: {
            'vs': 'https://cdnjs.cloudflare.com/ajax/libs/monaco-editor/0.49.0/min/vs'
        }
    });

    require(['vs/editor/editor.main'], async function () {
        var code;
        var assignment_id = getParamValue('id');
        var apiBase = decodeURIComponent(getParamValue('apiBase') || 'http%3A%2F%2F127.0.0.1%3A5000').replace(/\/$/, '');
        await fetch(apiBase + "/assignments/" + assignment_id.toString())
            .then(response => {
                if (response.ok) {
                    return response.json();
                }
                throw new Error('Request failed!');
            })
            .then(data => {
                //console.log("data:", data)
                code = data["starter_code"];
            })
            .catch(error => console.log("error:", error));



        var editor = monaco.editor.create(document.getElementById('container'), {
            value: code,
            language: 'python',
            theme: 'vs-dark',
            automaticLayout: true
        });

    });
});

    // document.getElementById('runCodeButton').addEventListener('click', async function () {
    //     // Save the original console.log    
    //     //console.log("button pressed event listener");
    //     const originalConsoleLog = console.log;
    //     userCode = monaco.editor.getModels()[0].getValue();

    //     //console.log("button pressed USERCODE: " + userCode);


    //     const json_code = JSON.stringify({ code: userCode });

    //     //console.log(json_code)


    //     const options = {
    //         method: 'POST',    
    //         headers: {
    //             'Content-Type': 'application/json',    
    //         },
    //         body: json_code,
    //         mode: 'cors'
    //     };
    //     //console.log(options)

    //     var response = await fetch(url + "grade/1", options)
    //         .then(response => {
    //             //console.log("response:", response);    
    //             if (response.ok) {
    //                 console.log(response.body);    
    //                 return response;
    //             }
    //         })
    //         .then(data => {

    //             console.log(data['result']);    
    //             if (data['ex_success'] === true) {
    //                 console.log(data['code_output']);    
    //                 //bad --TODO:fix later pls
    //                 document.getElementById('output').textContent = data["code_output"];
    //                 document.getElementById('output').textContent += "\n\n" + data["unittest_output"];
    //                 document.getElementById('output').textContent += "\n\n" + data["pass"];
    //             }
    //             else {
    //                 document.getElementById('output').textContent = data['result'];    
    //             }
    //         })
    //         .catch(error =>
    //             console.log("error:", error));    

    // });

    

    
