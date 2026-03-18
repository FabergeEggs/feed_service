from fastapi import FastAPI
import uvicorn

import sys
from pathlib import Path
sys.path.append(str(Path(__file__).parent.parent))


app = FastAPI()

if __name__ == "__main__":
    uvicorn.run("main:app", reload=True)
