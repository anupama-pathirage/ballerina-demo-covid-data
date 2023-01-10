import ballerina/http;

type CountryInfo record {
    string? iso3;
};

type CovidCountry record {
    string country;
    int cases;
    int population;
    CountryInfo countryInfo;
    int deaths;
};

type Country record {|
    string code;
    string name;
    int population;
    string region;
    string incomeLevel;
    decimal caseFatalityRatio;
|};

service /cfr on new http:Listener(9090) {

    resource function get countries(int? no_of_countries, int? min_population, int? min_deaths, int? min_cases) returns Country[]|error {
        http:Client covidData = check new ("https://disease.sh/v3/covid-19/");
        CovidCountry[] covidCountries = check covidData->get("countries");
        var filteredCountries = from var {countryInfo, country, population, cases, deaths} in covidCountries
            where countryInfo?.iso3 is string
            where population > (min_population ?: 100000) && cases > (min_cases ?: 1000) && deaths > (min_deaths ?: 100)
            let decimal caseFatalityRatio = cfr(deaths, cases)
            order by caseFatalityRatio descending
            limit no_of_countries ?: 10
            select {code: countryInfo["iso3"] ?: "", name: country, population, caseFatalityRatio};

        Country[] countries = [];
        http:Client worldbank = check new ("https://api.worldbank.org/v2/");
        foreach var {code, name, population, caseFatalityRatio} in filteredCountries {
            xml wbPayload = check worldbank->get(string `country/${code}`);
            var [incomeLevel, region] = extractWBData(wbPayload);
            countries.push({code, name, population, caseFatalityRatio, incomeLevel, region});
        }
        return countries;
    }

    resource function get countries/[string code]() returns Country|error {
        http:Client covidData = check new ("https://disease.sh/v3/covid-19/");
        CovidCountry payload = check covidData->get(string `countries/${code}`);
        var {country: name, population, deaths, cases} = payload;
        decimal caseFatalityRatio = cfr(deaths, cases);

        http:Client worldbank = check new ("https://api.worldbank.org/v2/");
        xml wbPayload = check worldbank->get(string `country/${code}`);
        var [incomeLevel, region] = extractWBData(wbPayload);

        return {code, name, population, region, incomeLevel, caseFatalityRatio};
    }
}

function cfr(int deaths, int cases) returns decimal => <decimal>deaths / <decimal>cases * 100;

function extractWBData(xml wbPayload) returns [string, string] {
    xmlns "http://www.worldbank.org" as wb;
    xml incomeLevelElement = wbPayload/**/<wb:incomeLevel>;
    xml regionElement = wbPayload/**/<wb:region>;
    return [incomeLevelElement.data(), regionElement.data()];
}