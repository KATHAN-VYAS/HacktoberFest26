const weatherUrl="https://api.open-meteo.com/v1/forecast?latitude=38.9869&longitude=-76.9426&current=temperature_2m,apparent_temperature,weather_code,wind_speed_10m,precipitation&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max,weather_code&forecast_days=3&temperature_unit=fahrenheit&wind_speed_unit=mph&precipitation_unit=inch&timezone=America%2FNew_York";
const condition:Record<number,string>={0:"Clear sky",1:"Mostly clear",2:"Partly cloudy",3:"Overcast",45:"Fog",48:"Freezing fog",51:"Light drizzle",53:"Drizzle",55:"Heavy drizzle",56:"Light freezing drizzle",57:"Freezing drizzle",61:"Light rain",63:"Rain",65:"Heavy rain",66:"Light freezing rain",67:"Freezing rain",71:"Light snow",73:"Snow",75:"Heavy snow",77:"Snow grains",80:"Light rain showers",81:"Rain showers",82:"Heavy rain showers",85:"Light snow showers",86:"Heavy snow showers",95:"Thunderstorm",96:"Thunderstorm with hail",99:"Thunderstorm with heavy hail"};
function fahrenheit(value:number){return `${Math.round(value)}°F (${Math.round((value-32)*5/9)}°C)`;}
export function isWeatherQuestion(question:string){return /\b(weather|temperature|forecast|raining|snowing)\b/i.test(question);}

export async function weatherAnswer(question:string) {
  if(!isWeatherQuestion(question))return null;
  // Campus-area model coordinates. Never request or infer a visitor's location.
  try {
    const r=await fetch(weatherUrl,{signal:AbortSignal.timeout(8000)});
    if(!r.ok)throw new Error("Weather unavailable");
    const data=await r.json() as any;
    const c=data.current;
    if(!c||typeof c.time!=="string"||!Number.isFinite(c.temperature_2m)||!Number.isFinite(c.apparent_temperature)||!Number.isFinite(c.wind_speed_10m)||!Number.isFinite(c.weather_code)||!Number.isFinite(data.utc_offset_seconds))throw new Error("Invalid weather data");
    const instant=Date.parse(c.time+"Z")-data.utc_offset_seconds*1000;
    if(!Number.isFinite(instant)||Date.now()-instant>2*60*60*1000||instant-Date.now()>15*60*1000)throw new Error("Stale weather data");
    const observed=new Intl.DateTimeFormat("en-US",{timeZone:"America/New_York",month:"short",day:"numeric",hour:"numeric",minute:"2-digit",timeZoneName:"short"}).format(new Date(instant));
    let answer=`Near the UMD campus in College Park: ${condition[c.weather_code]||"Current conditions"}.\n\nTemperature: ${fahrenheit(c.temperature_2m)}\nFeels like: ${fahrenheit(c.apparent_temperature)}\nWind: ${Math.round(c.wind_speed_10m)} mph\n\nUpdated ${observed}. These are modeled conditions for the campus area, not a sensor at your exact location. [1]`;
    if(/\b(tomorrow|forecast|later|tonight)\b/i.test(question)) {
      const day=/\btomorrow\b/i.test(question)?1:0,d=data.daily;
      if(!d||!Number.isFinite(d.temperature_2m_max?.[day])||!Number.isFinite(d.temperature_2m_min?.[day])||!Number.isFinite(d.precipitation_probability_max?.[day]))throw new Error("Forecast unavailable");
      answer=`${day===1?"Tomorrow":"Today"} near UMD (${d.time[day]}): ${condition[d.weather_code[day]]||"See forecast"}.\n\nHigh: ${fahrenheit(d.temperature_2m_max[day])}\nLow: ${fahrenheit(d.temperature_2m_min[day])}\nChance of precipitation: ${d.precipitation_probability_max[day]}%\n\nForecast retrieved ${observed}. Check the linked forecast before heading out. [1]`;
    }
    return {answer,mode:"live-weather",status:"private",sources:[{id:"live-weather",title:"Live weather near UMD · Open-Meteo",url:weatherUrl,content:answer,checkedAt:observed,live:true}]};
  } catch {
    // An upstream outage is not a student knowledge question. Keep it private.
    return {answer:"I couldn't fetch fresh weather for the UMD campus just now. I won't guess current conditions or post this publicly. Use the live forecast link below, or select Retry AI / refresh to try again.",mode:"live-weather-unavailable",status:"private",sources:[{id:"weather-service",title:"Open the live College Park forecast",url:weatherUrl,content:"Live weather service; current conditions could not be verified.",checkedAt:"Live service",live:true}]};
  }
}
