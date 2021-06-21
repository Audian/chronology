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

## Time periods
- `:today`
- `:yesterday`
- `:this_week`
- `:this_month`
- `:this_year`
- `:last_week`
- `:last_month`
- `:last_year`
- `:previous_year`
- `:past_week`
- `:past_month`
- `:past_year`
- `:this_quarter`
- `:last_quarter`
