"""In-process TTL cache for adapter responses (weather 6h/24h, NDVI 24h).

ponytail: cachetools.TTLCache is single-process and lost on restart. That is
an accepted ceiling at hackathon scale (TRD §14 — "Redis is unnecessary at
hackathon scale and adds a failure mode"). Upgrade path: swap for Redis if
the API ever runs multi-process.
"""
from cachetools import TTLCache

weather_cache: TTLCache = TTLCache(maxsize=512, ttl=6 * 3600)
weather_archive_cache: TTLCache = TTLCache(maxsize=512, ttl=24 * 3600)
ndvi_cache: TTLCache = TTLCache(maxsize=256, ttl=24 * 3600)
price_cache: TTLCache = TTLCache(maxsize=256, ttl=24 * 3600)
qaoa_cache: TTLCache = TTLCache(maxsize=256, ttl=3600)
