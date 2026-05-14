const fs = require('fs');
const handlebars = require('handlebars');

// 注册helper函数
handlebars.registerHelper('eq', function(a, b) {
    return a === b;
});

// 读取模板文件
const templateSource = fs.readFileSync('release-template.html', 'utf8');
const template = handlebars.compile(templateSource);

// 渲染页面
function generateReleasePage(data) {
    return template(data);
}

// API端点
app.get('/release/:apiName/:version', (req, res) => {
    const releaseData = getReleaseData(req.params.apiName, req.params.version);
    const html = generateReleasePage(releaseData);
    res.send(html);
});