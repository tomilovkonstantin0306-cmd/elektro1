import os
import io
import asyncio
from dotenv import load_dotenv
from aiogram import Bot, Dispatcher, F
from aiogram.types import Message
from aiogram.enums import ParseMode
from google import genai
from google.genai import types

load_dotenv()

TG_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN")
GEMINI_KEY = os.getenv("GEMINI_API_KEY")

bot = Bot(token=TG_TOKEN)
dp = Dispatcher()
ai_client = genai.Client(api_key=GEMINI_KEY)

SYSTEM_PROMPT = """
Ты — профессиональный инженер-схемотехник и эксперт по чтению принципиальных, монтажных и однолинейных схем (ГОСТ/ЕСКД, IEC, автоэлектрика).

Когда пользователь отправляет схему:
1. Определи тип схемы (силовая, схема управления, электропроводка, печатная плата).
2. Выдели и расшифруй основные элементы:
   - Автоматы, УЗО, реле (номиналы, контакты NO/NC).
   - Источники питания, фазы (L1, L2, L3, N, PE).
   - Потребители и исполнительные механизмы.
3. Объясни логику работы узла, если задан вопрос или цепочка очевидна.
4. Предупреди о нюансах безопасности, если видны опасные места.
Форматируй ответ структурированно, с подзаголовками и списками.
"""

async def analyze_circuit(image_bytes: bytes, mime_type: str, user_question: str) -> str:
    prompt = user_question if user_question else "Расшифруй эту схему, выдели ключевые компоненты и опиши принцип работы цепи."
    
    response = ai_client.models.generate_content(
        model="gemini-2.5-flash",
        contents=[
            types.Part.from_bytes(data=image_bytes, mime_type=mime_type),
            prompt
        ],
        config=types.GenerateContentConfig(
            system_instruction=SYSTEM_PROMPT,
            temperature=0.2
        )
    )
    return response.text

@dp.message(F.text == "/start")
async def start_handler(message: Message):
    await message.answer(
        "👋 **Привет! Я бот-помощник по чтению электросхем.**\n\n"
        "Отправьте мне фото или файл схемы (как изображение или документ), "
        "и при необходимости добавьте вопрос в подпись к фото.\n\n"
        "💡 *Совет:* Для больших схем отправляйте файл как *«Документ» (без сжатия)*, "
        "чтобы маркировки и номиналы оставались чёткими.",
        parse_mode=ParseMode.MARKDOWN
    )

@dp.message(F.photo)
async def handle_photo(message: Message):
    status_msg = await message.answer("🔍 Изучаю схему, это займет несколько секунд...")
    try:
        photo = message.photo[-1]
        file_io = io.BytesIO()
        await bot.download(photo, destination=file_io)
        
        caption = message.caption or ""
        result = await analyze_circuit(file_io.getvalue(), "image/jpeg", caption)
        
        if len(result) > 4000:
            for part in [result[i:i+4000] for i in range(0, len(result), 4000)]:
                await message.answer(part)
        else:
            await status_msg.edit_text(result)
    except Exception as e:
        await status_msg.edit_text(f"❌ Ошибка при анализе изображения: {e}")

@dp.message(F.document)
async def handle_document(message: Message):
    mime = message.document.mime_type or ""
    if not (mime.startswith("image/") or mime == "application/pdf"):
        await message.answer("Пожалуйста, отправьте файл в формате изображения (PNG, JPG) или PDF.")
        return

    status_msg = await message.answer("📄 Загружаю документ без сжатия и анализирую...")
    try:
        file_io = io.BytesIO()
        await bot.download(message.document, destination=file_io)
        
        caption = message.caption or ""
        result = await analyze_circuit(file_io.getvalue(), mime, caption)
        
        if len(result) > 4000:
            for part in [result[i:i+4000] for i in range(0, len(result), 4000)]:
                await message.answer(part)
        else:
            await status_msg.edit_text(result)
    except Exception as e:
        await status_msg.edit_text(f"❌ Ошибка при анализе документа: {e}")

async def main():
    print("Бот запущен...")
    await dp.start_polling(bot)

if __name__ == "__main__":
    asyncio.run(main())
