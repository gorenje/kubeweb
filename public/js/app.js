const NotApp = function(){ alert('Action not Supported.') }

function toggleLegend(chartid) {
  $('#'+chartid).find('g.highcharts-legend-item').click()
  return false;
}

function hideSeries(chartid,sername) {
  $($('#'+chartid).find('g.highcharts-legend-item')
    .filter(function(_,e){return $(e).find('text').text() === sername})[0])
    .click();
}

function updateCpuChart() { updateChart(window.chartcpu, "cpu") }
function updateMemChart() { updateChart(window.chartmem, "mem") }
