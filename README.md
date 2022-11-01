# Chronology

This is a simple wrapper around Timex to get date ranges for humanized references,
such as `last week`, `past year` etc.

## Installation


```elixir
def deps do
  [
    {:chronology, github: "audian/chronology"}
  ]
end
```


## Usage

```elixir
iex> Chronology.range(:past_year)
{:ok,
 %{
   finish: ~U[2021-06-21 22:06:41.036959Z],
   start: ~U[2020-06-21 22:06:41.036641Z]
 }}

 iex> Chronology.range(:past_month)
{:ok,
 %{
   finish: ~U[2021-06-21 22:06:36.181093Z],
   start: ~U[2021-05-21 22:06:36.180699Z]
 }}
```

## Time Periods

| time period    | Period description       |
|----------------|--------------------------|
| :today         | Today                    |
| :yesterday     | Yesterday                |
| :this_week     | The current week         |
| :this_month    | The current month        |
| :this_year     | The current year         |
| :this_quarter  | The current quarter      |
| :last_week     | The last week (Mon-Sun)  |
| :last_month    | The last full month      |
| :last_year     | The last full year       |
| :last_quarter  | The last quarter         |
| :past_week     | Past 7 days              |
| :past_month    | Past month (date to date)|
| :past_year     | Past 365 days            |
| :previous_year | 2 years ago              |
